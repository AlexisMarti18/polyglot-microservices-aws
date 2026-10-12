from flask import Flask

app = Flask(__name__)

# Límite del body: un cliente pesa pocos bytes; lo que supere 16 KB se rechaza con 413.
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024
