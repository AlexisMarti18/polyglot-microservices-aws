package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	db, err := conectarDB()
	if err != nil {
		log.Fatal("No se pudo conectar a la base de datos:", err)
	}
	defer db.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		responderJSON(w, http.StatusOK, map[string]string{"status": "ok", "servicio": "api-transacciones"})
	})
	registrarRutas(mux, db)

	port := getEnv("PORT", "8080")
	addr := fmt.Sprintf(":%s", port)
	log.Printf("API de transacciones escuchando en el puerto %s", port)
	log.Fatal(http.ListenAndServe(addr, mux))
}
