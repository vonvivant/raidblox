--!strict
-- Signal: evento tipado liviano para comunicación entre módulos del mismo lado
-- (sin pasar por la red). Cada listener corre en su propio hilo, así un error
-- en un sistema no corta a los demás.

local Signal = {}

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

function Signal.new<T...>(): Signal<T...>
	local listeners: { [Connection]: (T...) -> () } = {}

	local self = {} :: Signal<T...>

	function self.Connect(_: Signal<T...>, fn: (T...) -> ()): Connection
		local connection = { Connected = true } :: Connection
		function connection.Disconnect(conn: Connection)
			conn.Connected = false
			listeners[conn] = nil
		end
		listeners[connection] = fn
		return connection
	end

	function self.Fire(_: Signal<T...>, ...: T...)
		-- Copia: un listener puede conectar/desconectar mientras se recorre.
		for _, fn in table.clone(listeners) do
			task.spawn(fn, ...)
		end
	end

	function self.DisconnectAll(_: Signal<T...>)
		for connection in listeners do
			connection.Connected = false
		end
		table.clear(listeners)
	end

	return self
end

return Signal
