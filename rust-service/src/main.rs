//! Minimal service stub: loads config + secrets, serves `GET /health`.

use anyhow::{bail, Context, Result};
use axum::{routing::get, Json, Router};
use clap::Parser;
use serde::Deserialize;
use serde_json::{json, Value};
use std::{fs, net::SocketAddr, path::PathBuf};
use tracing_subscriber::EnvFilter;

#[derive(Debug, Parser)]
#[command(name = "app", about = "Minimal rust-service stub")]
struct Args {
    /// Path to non-secret JSON config (baked from config.nix).
    #[arg(long, default_value = "/etc/app/config.json")]
    config: PathBuf,

    /// Path to secrets JSON (mounted at runtime).
    #[arg(long, default_value = "/run/secrets/app.json")]
    secrets: PathBuf,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeConfig {
    server: ServerConfig,
    logging: LoggingConfig,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerConfig {
    api_port: u16,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LoggingConfig {
    filter: String,
}

fn load_config(path: &PathBuf) -> Result<RuntimeConfig> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("failed to read config from {}", path.display()))?;
    serde_json::from_str(&text)
        .with_context(|| format!("failed to parse config JSON from {}", path.display()))
}

fn load_secrets(path: &PathBuf) -> Result<Value> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("failed to read secrets from {}", path.display()))?;
    let value: Value = serde_json::from_str(&text)
        .with_context(|| format!("failed to parse secrets JSON from {}", path.display()))?;
    if !value.is_object() {
        bail!("secrets file must contain a JSON object");
    }
    Ok(value)
}

async fn health() -> Json<Value> {
    Json(json!({ "ok": true }))
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    let config = load_config(&args.config)?;
    let _secrets = load_secrets(&args.secrets)?;

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_new(&config.logging.filter).unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let app = Router::new().route("/health", get(health));
    let addr = SocketAddr::from(([0, 0, 0, 0], config.server.api_port));
    tracing::info!("listening on {addr}");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_runtime_config() {
        let raw = json!({
            "server": { "apiPort": 8080 },
            "logging": { "filter": "INFO" }
        });
        let cfg: RuntimeConfig = serde_json::from_value(raw).expect("config should parse");
        assert_eq!(cfg.server.api_port, 8080);
        assert_eq!(cfg.logging.filter, "INFO");
    }

    fn temp_secrets_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("app-secrets-{}-{name}.json", std::process::id()))
    }

    #[test]
    fn rejects_non_object_secrets() {
        let path = temp_secrets_path("array");
        fs::write(&path, r#"["not", "an", "object"]"#)
            .expect("secrets test file should be written");

        let result = load_secrets(&path);
        fs::remove_file(&path).expect("secrets test file should be removed");
        let error = result.expect_err("non-object secrets should be rejected");
        assert_eq!(error.to_string(), "secrets file must contain a JSON object");
    }

    #[test]
    fn loads_object_secrets() {
        let path = temp_secrets_path("object");
        fs::write(&path, r#"{"token":"example"}"#).expect("secrets test file should be written");

        let result = load_secrets(&path);
        fs::remove_file(&path).expect("secrets test file should be removed");
        assert_eq!(
            result.expect("object secrets should load"),
            json!({"token": "example"})
        );
    }
}
