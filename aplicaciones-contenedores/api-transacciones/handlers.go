package main

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
)

type Transaccion struct {
	ID       int64   `json:"id"`
	OrigenIP string  `json:"origen_ip"`
	Pais     string  `json:"pais"`
	Monto    float64 `json:"monto"`
	Tipo     string  `json:"tipo"`
}

func registrarRutas(mux *http.ServeMux, db *sql.DB) {
	mux.HandleFunc("GET /transacciones", listarTransacciones(db))
	mux.HandleFunc("GET /transacciones/{id}", obtenerTransaccion(db))
	mux.HandleFunc("POST /transacciones", crearTransaccion(db))
	mux.HandleFunc("PUT /transacciones/{id}", actualizarTransaccion(db))
	mux.HandleFunc("DELETE /transacciones/{id}", borrarTransaccion(db))
}

func listarTransacciones(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.Query("SELECT id, origen_ip, pais, monto, tipo FROM transacciones")
		if err != nil {
			http.Error(w, "Error al listar transacciones", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		resultado := []Transaccion{}
		for rows.Next() {
			var t Transaccion
			var pais sql.NullString
			if err := rows.Scan(&t.ID, &t.OrigenIP, &pais, &t.Monto, &t.Tipo); err != nil {
				http.Error(w, "Error al leer transacciones", http.StatusInternalServerError)
				return
			}
			t.Pais = pais.String
			resultado = append(resultado, t)
		}
		responderJSON(w, http.StatusOK, resultado)
	}
}

func obtenerTransaccion(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		var t Transaccion
		var pais sql.NullString
		err := db.QueryRow("SELECT id, origen_ip, pais, monto, tipo FROM transacciones WHERE id = ?", id).
			Scan(&t.ID, &t.OrigenIP, &pais, &t.Monto, &t.Tipo)
		if err == sql.ErrNoRows {
			http.Error(w, "Transaccion no encontrada", http.StatusNotFound)
			return
		}
		if err != nil {
			http.Error(w, "Error al buscar la transaccion", http.StatusInternalServerError)
			return
		}
		t.Pais = pais.String
		responderJSON(w, http.StatusOK, t)
	}
}

func crearTransaccion(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var entrada Transaccion
		if err := json.NewDecoder(r.Body).Decode(&entrada); err != nil {
			http.Error(w, "JSON invalido", http.StatusBadRequest)
			return
		}

		// Enriquecemos la transaccion con el pais de origen consultando una API externa.
		entrada.Pais = obtenerPais(entrada.OrigenIP)

		result, err := db.Exec(
			"INSERT INTO transacciones (origen_ip, pais, monto, tipo) VALUES (?, ?, ?, ?)",
			entrada.OrigenIP, nullIfEmpty(entrada.Pais), entrada.Monto, entrada.Tipo,
		)
		if err != nil {
			http.Error(w, "Error al crear la transaccion", http.StatusInternalServerError)
			return
		}
		id, _ := result.LastInsertId()
		entrada.ID = id
		responderJSON(w, http.StatusCreated, entrada)
	}
}

func actualizarTransaccion(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		var entrada Transaccion
		if err := json.NewDecoder(r.Body).Decode(&entrada); err != nil {
			http.Error(w, "JSON invalido", http.StatusBadRequest)
			return
		}
		result, err := db.Exec(
			"UPDATE transacciones SET origen_ip=?, pais=?, monto=?, tipo=? WHERE id=?",
			entrada.OrigenIP, nullIfEmpty(entrada.Pais), entrada.Monto, entrada.Tipo, id,
		)
		if err != nil {
			http.Error(w, "Error al actualizar la transaccion", http.StatusInternalServerError)
			return
		}
		filas, _ := result.RowsAffected()
		if filas == 0 {
			http.Error(w, "Transaccion no encontrada", http.StatusNotFound)
			return
		}
		idInt, _ := strconv.ParseInt(id, 10, 64)
		entrada.ID = idInt
		responderJSON(w, http.StatusOK, entrada)
	}
}

func borrarTransaccion(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		result, err := db.Exec("DELETE FROM transacciones WHERE id=?", id)
		if err != nil {
			http.Error(w, "Error al borrar la transaccion", http.StatusInternalServerError)
			return
		}
		filas, _ := result.RowsAffected()
		if filas == 0 {
			http.Error(w, "Transaccion no encontrada", http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func responderJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
