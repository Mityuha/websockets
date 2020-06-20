import logging
import json
import asyncio
import aiohttp
import ssl
import os
from aiohttp import web
import struct

ROOM_NAME_TEMPLATE = "Room-{}"
ROOM_LIMIT = 3
MAX_HEALTH = 100
SPEED = 200.0
PRESS_TIME = 0.016


def room_num(room_name):
    return int(room_name.split("-")[1])


def system_message(text):
    return {"message": text, "type": "system"}


# def user_message(text, username, color="ff0000"):
#    return {"message": text, "type": "message", "username": username, "color": color}


class Room:
    __slots__ = ("name", "number", "limit", "entities", "free_places")

    def __init__(self, name, limit=ROOM_LIMIT):
        self.name = name
        self.number = room_num(name)
        self.limit = limit
        self.entities = [None] * limit
        self.free_places = {i for i in range(limit)}

    def is_full(self):
        return not self.free_places

    def is_empty(self):
        return len(self.free_places) == self.limit

    def add_entity(self, entity):
        new_id = self.free_places.pop()
        self.entities[new_id] = entity
        return new_id

    def remove_entity(self, entity):
        self.entities[entity.entity_id] = None
        self.free_places.add(entity.entity_id)

    def active_entities_count(self):
        return self.limit - len(self.free_places)


class Connection:
    __slots__ = ("ip_addr", "port", "wsocket")

    def __init__(self, ip_addr, port, wsocket):
        self.ip_addr = ip_addr
        self.port = port
        self.wsocket = wsocket

    def __hash__(self):
        return hash((self.ip_addr, self.port))

    def __eq__(self, other):
        return (self.ip_addr, self.port) == (other.ip_addr, other.port)

    async def send(self, state, is_ping=False):
        if state or is_ping:
            await self.wsocket.send_bytes(state)


class Entity:
    __slots__ = (
        "connection",
        "entity_id",
        "pending_inputs",
        "last_processed_input",
        "health",
        "speed",
        "position",
    )

    def __init__(self, connection):
        self.connection = connection
        self.entity_id = None
        self.pending_inputs = []
        self.last_processed_input = -1
        self.health = MAX_HEALTH
        self.speed = SPEED
        self.position = (200.0, 200.0)

    def __hash__(self):
        return hash(self.entity_id)

    def __eq__(self, other):
        return self.entity_id == other.entity_id

    def apply_input(self, einput):
        assert einput[1] == self.entity_id
        x, y = 0, 0
        # 0 -- down, 1 -- left, 2 -- up, 3 -- right
        x += (einput[2] >> 3) & 1
        x -= (einput[2] >> 1) & 1
        y += (einput[2] >> 0) & 1
        y -= (einput[2] >> 2) & 1
        x *= self.speed
        y *= self.speed
        self.position = (
            self.position[0] + x * PRESS_TIME,
            self.position[1] + y * PRESS_TIME,
        )
        self.last_processed_input = einput[0]

    def encode_position(self):
        return struct.pack("I", int(self.position[0])) + struct.pack(
            "I", int(self.position[1])
        )


class Roomer:
    def __init__(self, limit=ROOM_LIMIT):
        self.limit = limit
        self.rooms = [Room(name=ROOM_NAME_TEMPLATE.format(0))]
        self.entity2room = {}
        self.connection2entity = {}

    def _find_free_room(self):
        """return not full room instance"""
        free_room = None
        for room in self.rooms:
            if not room.is_full():
                free_room = room
                break
        else:
            free_room = Room(name=ROOM_NAME_TEMPLATE.format(len(self.rooms)))
            self.rooms.append(free_room)

        return free_room

    async def new_participant(self, ip_addr, port, wsocket):
        """return participant room name"""
        log = logging.getLogger(__name__)
        connection = Connection(ip_addr, port, wsocket)
        free_room = self._find_free_room()

        entity = Entity(connection)
        entity.entity_id = free_room.add_entity(entity)

        log.debug(
            "%s: new entity, room %s (%s #)",
            (ip_addr, port),
            free_room.name,
            free_room.active_entities_count(),
        )

        # TODO: packages
        await entity.connection.send(
            bytes([0, entity.entity_id]) + entity.encode_position()
        )

        # history = [system_message(free_room.name)] + free_room.messages[-10:]
        # await participant.send(history)
        # log.debug("%s: history sended (%s messages)", (ip_addr, port,), len(history))

        self.entity2room[entity] = free_room
        self.connection2entity[connection] = entity

        return

    def participant_left(self, ip_addr, port):
        """process participant left"""
        log = logging.getLogger(__name__)
        connection = Connection(ip_addr, port, wsocket=None)
        try:
            entity = self.connection2entity[connection]
        except KeyError:
            log.info(
                "%s: participant has already left (from background ping)",
                (ip_addr, port),
            )
            return

        try:
            room = self.entity2room.pop(entity)
        except KeyError:
            log.info(
                "%s: participant has already left (from background ping)",
                (ip_addr, port),
            )
            return
        else:
            room.remove_entity(entity)

        log.debug(
            "%s left from room %s (%s #)",
            (ip_addr, port),
            room.name,
            room.active_entities_count(),
        )
        return

    async def new_input(self, ip_addr, port, entity_input):
        """process participant new message"""
        log = logging.getLogger(__name__)
        connection = Connection(ip_addr, port, wsocket=None)
        log.debug("%s: new message %s", (ip_addr, port), entity_input)
        try:
            entity = self.connection2entity[connection]
        except KeyError:
            log.exception("%s: No entity, what's happening?", (ip_addr, port))
            return
        entity.pending_inputs.append(entity_input)
        return


async def websocket_handler(request):

    log = logging.getLogger(__name__)
    ws = web.WebSocketResponse(autoping=True, heartbeat=10,)
    await ws.prepare(request)

    remote = request.transport.get_extra_info("peername")
    if not remote:
        await ws.send_json(
            system_message("Your ip addr and port are undefined, sorry!")
        )
        await ws.close()
        return

    roomer = request.app["roomer"]
    await roomer.new_participant(*remote, wsocket=ws)

    fmt = "<IBB"

    async for message in ws:
        if message.type == aiohttp.WSMsgType.BINARY:
            data, _ = struct.unpack(fmt, message.data[:6]), message.data[6:]
            await roomer.new_input(*remote, entity_input=data)
            # await asyncio.sleep(0.1)

        elif message.type == aiohttp.WSMsgType.ERROR:
            log.warning(
                "%s: ws connection closed with exception %s", remote, ws.exception()
            )

    roomer.participant_left(*remote)

    return ws


async def ping_participants(roomer):
    log = logging.getLogger(__name__)
    while True:
        for entity in roomer.entity2room.copy():
            log.debug(
                "%s: connection.wsocket.closed: %s",
                entity.entity_id,
                entity.connection.wsocket.closed,
            )
            if not entity.connection.wsocket.closed:
                continue
            log.debug(
                "%s: socket closed", (entity.connection.ip_addr, entity.connection.port)
            )
            roomer.participant_left(entity.connection.ip_addr, entity.connection.port)
            continue
        await asyncio.sleep(10)


async def _process_inputs(roomer):
    log = logging.getLogger(__name__)
    for room in roomer.rooms:
        if room.is_empty():
            continue
        log.debug("room %s is not empty", room.name)
        for entity in room.entities:
            if entity is None:
                continue
            log.debug(
                "%s: is not none, %s pending_inputs",
                entity.entity_id,
                len(entity.pending_inputs),
            )
            for einput in entity.pending_inputs.copy():
                entity.apply_input(einput)
            entity.pending_inputs.clear()

            print("entity last processed input = ", entity.last_processed_input)
            if entity.last_processed_input == -1:
                continue

            state = (
                bytes([1, entity.entity_id])
                + struct.pack("I", entity.last_processed_input)
                + entity.encode_position()
            )
            await entity.connection.send(state)
            log.debug("%s: position: %s", entity.entity_id, entity.position)


async def process_inputs(roomer):
    log = logging.getLogger(__name__)
    while True:
        try:
            await _process_inputs(roomer)
        except BaseException:
            log.exception("")
        await asyncio.sleep(0.1)


if __name__ == "__main__":
    logging.getLogger().handlers = []

    log_formatter = logging.Formatter(
        "[%(asctime)s][%(name)s][%(funcName)s][L%(lineno)d][%(levelname)s]: %(message)s"
    )

    root_logger = logging.getLogger()

    handlers = []

    sh = logging.StreamHandler()
    sh.setLevel(logging.DEBUG)
    handlers.append(sh)

    for handler in handlers:
        handler.setFormatter(log_formatter)
        root_logger.addHandler(handler)

    root_logger.setLevel(logging.DEBUG)

    _roomer = Roomer()

    app = web.Application()
    app["roomer"] = _roomer
    app.add_routes([web.get("/ws", websocket_handler)])

    background_tasks = [
        asyncio.ensure_future(ping_participants(_roomer)) for _ in range(1)
    ]
    background_tasks += [
        asyncio.ensure_future(process_inputs(_roomer)) for _ in range(1)
    ]

    use_ssl = False

    if use_ssl:
        cert_path = os.getenv("CERTFILE_PATH")
        privkey_path = os.getenv("PRIVKEY_PATH")

        ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ssl_context.load_cert_chain(cert_path, privkey_path)
        web.run_app(app, host="0.0.0.0", port=8443, ssl_context=ssl_context)
    else:
        web.run_app(app, host="0.0.0.0", port=8080)

    for task in background_tasks:
        task.cancel()
