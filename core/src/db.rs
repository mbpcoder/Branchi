//! SQLite storage layer, built on `sqlx`.
//!
//! This mirrors how RustDesk's server persists data (SQLite via `sqlx`,
//! with the option to point at Postgres/MySQL later), just used here for
//! the desktop client's local state: known repos and app settings.

use anyhow::Result;
use chrono::{DateTime, Utc};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};
use sqlx::Row;
use std::path::Path;
use std::str::FromStr;

pub struct Database {
    pool: SqlitePool,
}

#[derive(Debug, Clone)]
pub struct Repo {
    pub id: i64,
    pub name: String,
    pub local_path: String,
    pub remote_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_opened_at: Option<DateTime<Utc>>,
}

impl Database {
    /// Open (creating if needed) the SQLite database at `path` and run
    /// pending migrations.
    pub async fn connect(path: impl AsRef<Path>) -> Result<Self> {
        let options = SqliteConnectOptions::from_str(&format!(
            "sqlite://{}",
            path.as_ref().display()
        ))?
        .create_if_missing(true);

        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .connect_with(options)
            .await?;

        sqlx::migrate!("./migrations").run(&pool).await?;

        Ok(Self { pool })
    }

    /// Open an in-memory database (used in tests).
    pub async fn connect_in_memory() -> Result<Self> {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await?;

        sqlx::migrate!("./migrations").run(&pool).await?;

        Ok(Self { pool })
    }

    pub async fn add_repo(&self, name: &str, local_path: &str, remote_url: Option<&str>) -> Result<i64> {
        let result = sqlx::query(
            "INSERT INTO repos (name, local_path, remote_url) VALUES (?1, ?2, ?3)",
        )
        .bind(name)
        .bind(local_path)
        .bind(remote_url)
        .execute(&self.pool)
        .await?;

        Ok(result.last_insert_rowid())
    }

    pub async fn list_repos(&self) -> Result<Vec<Repo>> {
        let rows = sqlx::query(
            "SELECT id, name, local_path, remote_url, created_at, last_opened_at FROM repos ORDER BY id",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| Repo {
                id: row.get("id"),
                name: row.get("name"),
                local_path: row.get("local_path"),
                remote_url: row.get("remote_url"),
                created_at: row.get("created_at"),
                last_opened_at: row.get("last_opened_at"),
            })
            .collect())
    }

    pub async fn remove_repo(&self, id: i64) -> Result<()> {
        sqlx::query("DELETE FROM repos WHERE id = ?1")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        sqlx::query(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        )
        .bind(key)
        .bind(value)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn get_setting(&self, key: &str) -> Result<Option<String>> {
        let row = sqlx::query("SELECT value FROM settings WHERE key = ?1")
            .bind(key)
            .fetch_optional(&self.pool)
            .await?;

        Ok(row.map(|r| r.get("value")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn add_and_list_repos() {
        let db = Database::connect_in_memory().await.unwrap();

        let id = db
            .add_repo("branchi", "/home/user/branchi", Some("https://github.com/mbp165/branchi"))
            .await
            .unwrap();

        let repos = db.list_repos().await.unwrap();
        assert_eq!(repos.len(), 1);
        assert_eq!(repos[0].id, id);
        assert_eq!(repos[0].name, "branchi");

        db.remove_repo(id).await.unwrap();
        assert!(db.list_repos().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn settings_roundtrip() {
        let db = Database::connect_in_memory().await.unwrap();

        assert_eq!(db.get_setting("theme").await.unwrap(), None);

        db.set_setting("theme", "dark").await.unwrap();
        assert_eq!(db.get_setting("theme").await.unwrap(), Some("dark".to_string()));

        db.set_setting("theme", "light").await.unwrap();
        assert_eq!(db.get_setting("theme").await.unwrap(), Some("light".to_string()));
    }
}
