package ;
import js.node.SocketIo;

/**
 * ...
 * @author sledorze
 */
 
typedef SocketManagerBuilder = {
	public function create(sio : SocketIoManager) : SocketManager;
}

typedef SocketManager = {
	function send (socket_id : Dynamic, topic : Dynamic, message : Dynamic) : Void;
	function flush () : Void;
}
 