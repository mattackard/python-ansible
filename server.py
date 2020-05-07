import flask

app = flask.Flask(__name__)
app.config["DEBUG"] = True

@app.route('/', methods=['GET'])
def home():
    return flask.send_file('index.html')

@app.route('/ip', methods=['GET'])
def get_ip():
    return flask.request.remote_addr + '\n'

app.run(host='0.0.0.0')
