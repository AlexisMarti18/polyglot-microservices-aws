package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type geoResponse struct {
	CountryName string `json:"country_name"`
	Error       bool   `json:"error"`
	Reason      string `json:"reason"`
}

// obtenerPais consulta una API PUBLICA externa (ipapi.co, sin API key) para enriquecer la
// transaccion con el pais de origen a partir de la IP. Esta es la parte del microservicio
// que depende de un servicio de terceros: si esa API externa esta caida, tiene rate-limit,
// o no hay internet desde el contenedor, no tiene que romper el ABM -> devolvemos "" y la
// transaccion se guarda igual, sin el pais.
func obtenerPais(ip string) string {
	client := http.Client{Timeout: 5 * time.Second}
	url := fmt.Sprintf("https://ipapi.co/%s/json/", ip)

	resp, err := client.Get(url)
	if err != nil {
		fmt.Println("No se pudo consultar la API externa de geolocalizacion:", err)
		return ""
	}
	defer resp.Body.Close()

	var data geoResponse
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		fmt.Println("Respuesta invalida de la API externa de geolocalizacion:", err)
		return ""
	}
	if data.Error {
		fmt.Println("La API externa de geolocalizacion devolvio un error:", data.Reason)
		return ""
	}
	return data.CountryName
}
