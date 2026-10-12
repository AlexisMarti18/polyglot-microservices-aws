package main

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/go-sql-driver/mysql"
)

// Esta API se conecta a "db_transacciones", UNA de las 5 bases que viven en la MISMA
// instancia compartida de MariaDB (ver tp-2026/db).
func conectarDB() (*sql.DB, error) {
	host := getEnv("DB_HOST", "localhost")
	port := getEnv("DB_PORT", "3306")
	name := getEnv("DB_NAME", "db_transacciones")
	user := getEnv("DB_USER", "appuser")
	pass := getEnv("DB_PASSWORD", "apppass")

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true", user, pass, host, port, name)
	return sql.Open("mysql", dsn)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
