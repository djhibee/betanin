# standard library
import os.path

# 3rd party
from flask import abort

# betanin
import betanin.config.betanin as conf_betanin
from betanin.extensions import DB
from betanin.jobs import import_torrents
from betanin.models import Torrent
from betanin.rest.base import SecureResource
from betanin.rest.base import allow_api_key
from betanin.rest.namespaces import TORRENTS_NS
from betanin.rest_models import request as req_models
from betanin.rest_models import response as resp_models


def _is_within(path, root):
    root = os.path.realpath(root)
    return os.path.commonpath([path, root]) == root


def _validate_import(path, name):
    "returns an error message if `path` / `name` is not acceptable, else None"
    if not path or path.startswith("-"):
        return "`path` must not be empty or start with `-`"
    if not name or name in (".", "..") or "/" in name or "\0" in name:
        return "`name` must be a single file or directory name"
    roots = conf_betanin.find_import_roots(conf_betanin.read())
    if roots:
        full_path = os.path.realpath(os.path.join(path, name))
        if not any(_is_within(full_path, root) for root in roots):
            return "path is outside of the configured `import_roots`"
    return None


def _add_import(path, name):
    error = _validate_import(path, name)
    if error:
        return abort(400, error)
    import_torrents.add(name=name, path=path)
    return None


@TORRENTS_NS.route("/")
class TorrentsResource(SecureResource):
    @staticmethod
    @TORRENTS_NS.doc(parser=req_models.TORRENT)
    @TORRENTS_NS.response(422, "invalid api key")
    @allow_api_key
    def post():
        "imports a new torrent"
        args = req_models.TORRENT.parse_args()
        if args.get("name") and args.get("path"):
            return _add_import(args["path"], args["name"])
        both = args.get("both")
        if not both:
            return abort(
                400, "please provide one of (`path` and `name`) or (`both`)"
            )
        path, name = os.path.split(both)
        if path and name:
            return _add_import(path, name)
        return abort(400, "please provide a valid path")

    @staticmethod
    @TORRENTS_NS.doc(parser=req_models.TORRENTS)
    @TORRENTS_NS.marshal_list_with(resp_models.TORRENTS)
    def get():
        "gets the list of all torrents"
        args = req_models.TORRENTS.parse_args()
        torrents = Torrent.query.order_by(Torrent.updated.desc())
        results = torrents.paginate(**args, error_out=False)
        return {
            "total": results.total,
            "torrents": results.items,
        }


@TORRENTS_NS.route("/<int:torrent_id>")
class TorrentResource(SecureResource):
    @staticmethod
    @TORRENTS_NS.marshal_with(resp_models.TORRENT)
    def get(torrent_id):
        "gets a single torrent"
        query = Torrent.query.filter_by(id=torrent_id)
        torrent = query.first_or_404()
        return torrent

    @staticmethod
    def put(torrent_id):
        "trys to import a torrent again"
        import_torrents.retry(torrent_id)

    @staticmethod
    def delete(torrent_id):
        "deletes a torrent from the list"
        query = Torrent.query.filter_by(id=torrent_id)
        torrent = query.first_or_404()
        DB.session.delete(torrent)
        DB.session.commit()


@TORRENTS_NS.route("/<int:torrent_id>/console/stdout")
class StdoutResource(SecureResource):
    @staticmethod
    @TORRENTS_NS.marshal_list_with(resp_models.LINE)
    def get(torrent_id):
        "gets the stdout of an imported/importing torrent"
        matches = Torrent.query.filter_by(id=torrent_id)
        return matches.first_or_404().lines


@TORRENTS_NS.route("/<int:torrent_id>/console/stdin")
class StdinResource(SecureResource):
    @staticmethod
    @TORRENTS_NS.doc(parser=req_models.LINE)
    def post(torrent_id):
        "sends stdin to an importing torrent"
        args = req_models.LINE.parse_args()
        text = args["text"]
        import_torrents.send_input(torrent_id, text)
