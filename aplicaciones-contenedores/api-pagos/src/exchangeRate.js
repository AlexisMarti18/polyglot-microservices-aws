// URL de una API PUBLICA y gratuita (no requiere API key) que da el tipo de cambio ARS -> USD.
const EXCHANGE_API_URL = 'https://open.er-api.com/v6/latest/ARS';

/**
 * Llama a una API externa para convertir un monto de ARS a USD.
 * Esta es la parte del microservicio que depende de un servicio de terceros: si esa API
 * externa esta caida, tiene rate-limit, o no hay internet desde el contenedor, no tiene
 * que romper el ABM de pagos -> devolvemos null y el pago se guarda igual, sin monto_usd.
 */
async function convertirArsAUsd(montoArs) {
  try {
    const res = await fetch(EXCHANGE_API_URL, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`La API externa respondio con status ${res.status}`);
    const data = await res.json();
    const tasaUsd = data.rates && data.rates.USD;
    if (!tasaUsd) throw new Error('La API externa no devolvio la tasa USD');
    return Number((montoArs * tasaUsd).toFixed(2));
  } catch (err) {
    console.error('No se pudo consultar la API externa de tipo de cambio:', err.message);
    return null;
  }
}

module.exports = { convertirArsAUsd };
