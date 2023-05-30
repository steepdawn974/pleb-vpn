from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from werkzeug.security import generate_password_hash
import secrets, os

db = SQLAlchemy()
DB_NAME = "pleb-vpn.db"

def create_app():
    app = Flask(__name__)

    if os.path.exists(os.path.abspath('./.secretKey.conf')):
        with open(os.path.abspath('./.secretKey.conf'), 'r') as secretKey:
            secret_key = secretKey.read()
    else:
        secret_key = secrets.token_urlsafe(16)
        with open(os.path.abspath('./.secretKey.conf'), 'w') as secretKey:
            secretKey.write(secret_key)

    app.config['SECRET_KEY'] = secret_key
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///' + DB_NAME
    db.init_app(app)

    from .views import views
    from .auth import auth

    app.register_blueprint(views, url_prefix='/')
    app.register_blueprint(auth, url_prefix='/')

    from .models import User

    with app.app_context():
        db.create_all()

    with app.app_context():
        user = User.query.filter_by(user_name='admin').first()
        if not user:
            new_user = User(user_name = 'admin', password = generate_password_hash('asdfasdf', method='sha256'))
            db.session.add(new_user)
            db.session.commit()    
    
    login_manager = LoginManager()
    login_manager.login_view = 'auth.login'
    login_manager.init_app(app)

    @login_manager.user_loader
    def load_user(id):
        return User.query.get(int(id))
    
    return app