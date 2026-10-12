import os
import pymysql
from app import app
from db_config import mysql
from flask import jsonify, request


def leer_cliente():
	"""Valida el body de POST/PUT. Devuelve ((nombre, email, dni), None) o (None, respuesta de error).

	Los campos tienen que ser texto: un objeto o una lista llegaría a la consulta SQL como
	parámetro (ver ERRORES.md en la raíz, inyección SQL con PyMySQL).
	"""
	data = request.get_json(silent=True)
	if not isinstance(data, dict):
		return None, (jsonify({'error': 'El body tiene que ser un objeto JSON'}), 400)
	nombre = data.get('nombre')
	email = data.get('email')
	dni = data.get('dni')
	if not isinstance(nombre, str) or not isinstance(email, str):
		return None, (jsonify({'error': 'nombre y email son obligatorios y tienen que ser texto'}), 400)
	if dni is not None and not isinstance(dni, str):
		return None, (jsonify({'error': 'dni tiene que ser texto'}), 400)
	return (nombre, email, dni), None


@app.errorhandler(413)
def body_demasiado_grande(_e):
	return jsonify({'error': 'Body demasiado grande'}), 413


@app.route('/', methods=['GET'])
def health():
	return jsonify({'status': 'ok', 'servicio': 'api-clientes'}), 200


@app.route('/clientes', methods=['GET'])
def listar_clientes():
	conn = cursor = None
	try:
		conn = mysql.connect()
		cursor = conn.cursor(pymysql.cursors.DictCursor)
		cursor.execute("SELECT * FROM clientes")
		rows = cursor.fetchall()
		return jsonify(rows), 200
	except Exception as e:
		print(e)
		return jsonify({'error': 'Error al listar clientes'}), 500
	finally:
		if cursor: cursor.close()
		if conn: conn.close()


@app.route('/clientes/<int:id>', methods=['GET'])
def obtener_cliente(id):
	conn = cursor = None
	try:
		conn = mysql.connect()
		cursor = conn.cursor(pymysql.cursors.DictCursor)
		cursor.execute("SELECT * FROM clientes WHERE id = %s", (id,))
		row = cursor.fetchone()
		if not row:
			return jsonify({'error': 'Cliente no encontrado'}), 404
		return jsonify(row), 200
	except Exception as e:
		print(e)
		return jsonify({'error': 'Error al buscar el cliente'}), 500
	finally:
		if cursor: cursor.close()
		if conn: conn.close()


@app.route('/clientes', methods=['POST'])
def crear_cliente():
	campos, error = leer_cliente()
	if error:
		return error
	nombre, email, dni = campos
	conn = cursor = None
	try:
		conn = mysql.connect()
		cursor = conn.cursor()
		cursor.execute(
			"INSERT INTO clientes (nombre, email, dni) VALUES (%s, %s, %s)",
			(nombre, email, dni)
		)
		conn.commit()
		return jsonify({'id': cursor.lastrowid, 'nombre': nombre, 'email': email, 'dni': dni}), 201
	except Exception as e:
		print(e)
		return jsonify({'error': 'Error al crear el cliente'}), 500
	finally:
		if cursor: cursor.close()
		if conn: conn.close()


@app.route('/clientes/<int:id>', methods=['PUT'])
def actualizar_cliente(id):
	campos, error = leer_cliente()
	if error:
		return error
	nombre, email, dni = campos
	conn = cursor = None
	try:
		conn = mysql.connect()
		cursor = conn.cursor()
		cursor.execute(
			"UPDATE clientes SET nombre=%s, email=%s, dni=%s WHERE id=%s",
			(nombre, email, dni, id)
		)
		conn.commit()
		if cursor.rowcount == 0:
			return jsonify({'error': 'Cliente no encontrado'}), 404
		return jsonify({'id': id, 'nombre': nombre, 'email': email, 'dni': dni}), 200
	except Exception as e:
		print(e)
		return jsonify({'error': 'Error al actualizar el cliente'}), 500
	finally:
		if cursor: cursor.close()
		if conn: conn.close()


@app.route('/clientes/<int:id>', methods=['DELETE'])
def borrar_cliente(id):
	conn = cursor = None
	try:
		conn = mysql.connect()
		cursor = conn.cursor()
		cursor.execute("DELETE FROM clientes WHERE id=%s", (id,))
		conn.commit()
		if cursor.rowcount == 0:
			return jsonify({'error': 'Cliente no encontrado'}), 404
		return '', 204
	except Exception as e:
		print(e)
		return jsonify({'error': 'Error al borrar el cliente'}), 500
	finally:
		if cursor: cursor.close()
		if conn: conn.close()


if __name__ == "__main__":
	app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
