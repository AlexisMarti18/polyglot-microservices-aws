from app import app
from flaskext.mysql import MySQL
from dotenv import load_dotenv
import os

load_dotenv()
mysql = MySQL()

# Esta API se conecta a "db_clientes", UNA de las 5 bases que viven en la MISMA instancia
# compartida de MariaDB (ver tp-2026/db). Los valores "or ..." son solo fallback para local.
app.config['MYSQL_DATABASE_USER'] = os.environ.get('DB_USER') or 'testuser'
app.config['MYSQL_DATABASE_PASSWORD'] = os.environ.get('DB_PASSWORD') or 'testuserpass'
app.config['MYSQL_DATABASE_DB'] = os.environ.get('DB_NAME') or 'db_clientes'
app.config['MYSQL_DATABASE_HOST'] = os.environ.get('DB_HOST') or 'localhost'
app.config['MYSQL_DATABASE_PORT'] = int(os.environ.get('DB_PORT') or 3306)

mysql.init_app(app)
