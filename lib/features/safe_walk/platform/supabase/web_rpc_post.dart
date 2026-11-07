/// `webRpcPost`: browser fetch on web (local preview only), unavailable elsewhere.
library;

export 'web_rpc_post_stub.dart' if (dart.library.js_interop) 'web_rpc_post_web.dart';
