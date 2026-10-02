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
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RuntimeConfig {
    server: ServerConfig,
    logging: LoggingConfig,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ServerConfig {
    api_port: u16,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LoggingConfig {
    filter: String,
}

fn load_config(path: &PathBuf) -> Result<RuntimeConfig> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("failed to read config from {}", path.display()))?;
    let config: RuntimeConfig = serde_json::from_str(&text)
        .with_context(|| format!("failed to parse config JSON from {}", path.display()))?;
    validate_config(config)
        .with_context(|| format!("failed to validate config from {}", path.display()))
}

#[cfg(test)]
fn parse_config(text: &str) -> Result<RuntimeConfig> {
    let config: RuntimeConfig = serde_json::from_str(text)?;
    validate_config(config)
}

fn validate_config(config: RuntimeConfig) -> Result<RuntimeConfig> {
    if config.server.api_port == 0 {
        bail!("config.server.apiPort: expected an integer port in 1..65535, got 0");
    }
    if config.logging.filter.is_empty() {
        bail!("config.logging.filter: expected a non-empty string, got an empty string");
    }
    Ok(config)
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

fn parse_log_filter(filter: &str) -> Result<EnvFilter> {
    EnvFilter::try_new(filter).with_context(|| {
        format!("invalid logging filter in config field `logging.filter`: {filter:?}")
    })
}

async fn health() -> Json<Value> {
    Json(json!({ "ok": true }))
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    tracing::info!("shutdown signal received; stopping server");
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    let config = load_config(&args.config)?;
    let _secrets = load_secrets(&args.secrets)?;

    tracing_subscriber::fmt()
        .with_env_filter(parse_log_filter(&config.logging.filter)?)
        .init();

    let app = Router::new().route("/health", get(health));
    let addr = SocketAddr::from(([0, 0, 0, 0], config.server.api_port));
    tracing::info!("listening on {addr}");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

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

    #[test]
    fn rejects_zero_api_port() {
        let raw = r#"{"server":{"apiPort":0},"logging":{"filter":"INFO"}}"#;

        let error = parse_config(raw).expect_err("port zero should be rejected");

        assert!(error.to_string().contains("config.server.apiPort"));
        assert!(error.to_string().contains("1..65535"));
    }

    #[test]
    fn rejects_empty_logging_filter() {
        let raw = r#"{"server":{"apiPort":8080},"logging":{"filter":""}}"#;

        let error = parse_config(raw).expect_err("empty filter should be rejected");

        assert!(error.to_string().contains("config.logging.filter"));
        assert!(error.to_string().contains("non-empty string"));
    }

    #[test]
    fn rejects_unexpected_config_fields_at_every_level() {
        for raw in [
            r#"{"server":{"apiPort":8080},"logging":{"filter":"INFO"},"extra":true}"#,
            r#"{"server":{"apiPort":8080,"extra":true},"logging":{"filter":"INFO"}}"#,
            r#"{"server":{"apiPort":8080},"logging":{"filter":"INFO","extra":true}}"#,
        ] {
            let error = parse_config(raw).expect_err("unexpected fields should be rejected");

            assert!(error.to_string().contains("unknown field `extra`"));
        }
    }

    #[test]
    fn parses_valid_log_filter() {
        let filter = parse_log_filter("app=debug,info").expect("filter should parse");

        assert_eq!(filter.to_string(), "app=debug,info");
    }

    #[test]
    fn invalid_log_filter_returns_config_error() {
        let invalid_filter = "app=invalid-level";

        let error = parse_log_filter(invalid_filter).expect_err("invalid filter should fail");

        assert!(error.to_string().contains("logging.filter"));
        assert!(error.to_string().contains(invalid_filter));
    }

    fn temp_secrets_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("app-secrets-{}-{name}.json", std::process::id()))
    }

    fn temp_config_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("app-config-{}-{name}.json", std::process::id()))
    }

    #[tokio::test]
    async fn health_route_returns_ok_json() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("test listener should bind");
        let address = listener
            .local_addr()
            .expect("test listener should have an address");
        let app = Router::new().route("/health", get(health));
        let server = tokio::spawn(async move {
            axum::serve(listener, app)
                .await
                .expect("test server should serve requests");
        });

        let response = async {
            let mut stream = tokio::net::TcpStream::connect(address)
                .await
                .expect("test client should connect");
            stream
                .write_all(b"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                .await
                .expect("test client should send request");
            let mut response = Vec::new();
            stream
                .read_to_end(&mut response)
                .await
                .expect("test client should read response");
            String::from_utf8(response).expect("HTTP response should be UTF-8")
        }
        .await;
        server.abort();

        let (headers, body) = response
            .split_once("\r\n\r\n")
            .expect("response should contain HTTP headers");
        assert!(headers.starts_with("HTTP/1.1 200 OK"), "{headers}");
        assert_eq!(body, r#"{"ok":true}"#);
    }

    #[test]
    fn missing_config_file_returns_read_error() {
        let path = temp_config_path("missing");
        let _ = fs::remove_file(&path);

        let error = load_config(&path).expect_err("missing config should fail");

        assert!(error.to_string().starts_with("failed to read config from"));
        assert!(error.to_string().contains(&path.display().to_string()));
    }

    #[test]
    fn malformed_config_file_returns_parse_error() {
        let path = temp_config_path("malformed");
        fs::write(&path, "{").expect("malformed config file should be written");

        let result = load_config(&path);
        fs::remove_file(&path).expect("malformed config file should be removed");
        let error = result.expect_err("malformed config should fail");

        assert!(error
            .to_string()
            .starts_with("failed to parse config JSON from"));
        assert!(error.to_string().contains(&path.display().to_string()));
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

    #[test]
    fn missing_secrets_file_returns_read_error() {
        let path = temp_secrets_path("missing");
        let _ = fs::remove_file(&path);

        let error = load_secrets(&path).expect_err("missing secrets should fail");

        assert!(error.to_string().starts_with("failed to read secrets from"));
        assert!(error.to_string().contains(&path.display().to_string()));
    }

    #[test]
    fn malformed_secrets_file_returns_parse_error() {
        let path = temp_secrets_path("malformed");
        fs::write(&path, "{").expect("malformed secrets file should be written");

        let result = load_secrets(&path);
        fs::remove_file(&path).expect("malformed secrets file should be removed");
        let error = result.expect_err("malformed secrets should fail");

        assert!(error
            .to_string()
            .starts_with("failed to parse secrets JSON from"));
        assert!(error.to_string().contains(&path.display().to_string()));
    }
}
