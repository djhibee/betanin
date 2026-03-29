# 3rd party
from flask import request
from flask_restx import abort
from flask_jwt_extended import create_access_token
from werkzeug.exceptions import TooManyRequests

# betanin
import betanin.config.betanin as conf_betanin
from betanin import rate_limit
from betanin.rest.base import BaseResource
from betanin.rest.namespaces import AUTHENTICATION_NS
from betanin.rest_models import request as req_models
from betanin.rest_models import response as resp_models


@AUTHENTICATION_NS.route("/login")
class LoginResource(BaseResource):
    @staticmethod
    @AUTHENTICATION_NS.doc(parser=req_models.CREDENTIALS)
    @AUTHENTICATION_NS.doc(security=None)
    @AUTHENTICATION_NS.response(422, "invalid username / password")
    @AUTHENTICATION_NS.response(429, "too many failed attempts")
    @AUTHENTICATION_NS.marshal_list_with(resp_models.AUTH_TOKEN)
    def post():
        "generates a json web token for the given username / password"
        client = request.remote_addr
        retry_after = rate_limit.LOGIN.retry_after(client)
        if retry_after:
            error = TooManyRequests(retry_after=retry_after)
            error.data = {
                "message": f"too many failed attempts, try again in {retry_after}s"
            }
            raise error
        args = req_models.CREDENTIALS.parse_args()
        conf = conf_betanin.read()
        if not conf_betanin.find_creds_correct(
            conf, args["username"], args["password"]
        ):
            rate_limit.LOGIN.add_failure(client)
            return abort(422, "invalid username / password")
        rate_limit.LOGIN.reset(client)
        return {"token": create_access_token(args["username"])}
