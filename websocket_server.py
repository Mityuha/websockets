import logging
import json
import asyncio
import aiohttp
import ssl
import os
from aiohttp import web

ROOM_NAME_TEMPLATE = "Room-{}"
ROOM_LIMIT = 3


def room_num(room_name):
    return int(room_name.split("-")[1])


def system_message(text):
    return {"message": text, "type": "system"}


# def user_message(text, username, color="ff0000"):
#    return {"message": text, "type": "message", "username": username, "color": color}


class Room:
    def __init__(self, name, limit=ROOM_LIMIT):
        self.name = name
        self.limit = limit
        self.participants = set()
        self.messages = []

    def is_full(self):
        return len(self.participants) == self.limit

    def is_empty(self):
        return not self.participants


class Participant:
    __slots__ = ("ip_addr", "port", "wsocket")

    def __init__(self, ip_addr, port, wsocket):
        self.ip_addr = ip_addr
        self.port = port
        self.wsocket = wsocket

    def __hash__(self):
        return hash((self.ip_addr, self.port))

    def __eq__(self, other):
        return (self.ip_addr, self.port) == (other.ip_addr, other.port)

    async def send(self, messages, is_ping=False):
        if type(messages) is not list:
            messages = [messages]

        if messages or is_ping:
            await self.wsocket.send_json(messages)


class Roomer:
    def __init__(self, limit=ROOM_LIMIT):
        self.limit = limit
        self.rooms = [Room(name=ROOM_NAME_TEMPLATE.format(0))]
        self.participant2room = {}

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

        if free_room.is_empty():
            free_room.messages.clear()

        return free_room

    async def new_participant(self, ip_addr, port, wsocket):
        """return participant room name"""
        log = logging.getLogger(__name__)
        participant = Participant(ip_addr, port, wsocket)
        free_room = self._find_free_room()

        log.debug(
            "%s: new participant, room %s (%s #)",
            (ip_addr, port),
            free_room.name,
            len(free_room.participants) + 1,
        )

        history = [system_message(free_room.name)] + free_room.messages[-10:]
        await participant.send(history)
        log.debug("%s: history sended (%s messages)", (ip_addr, port,), len(history))

        free_room.participants.add(participant)
        self.participant2room[participant] = free_room

        return

    def participant_left(self, ip_addr, port):
        """process participant left"""
        log = logging.getLogger(__name__)
        participant = Participant(ip_addr, port, wsocket=None)
        try:
            room = self.participant2room.pop(participant)
        except KeyError:
            log.info(
                "%s: participant has already left (from background ping)",
                (ip_addr, port),
            )
            return
        else:
            room.participants.discard(participant)
        log.debug(
            "%s left from room %s (%s #)",
            (ip_addr, port),
            room.name,
            len(room.participants),
        )
        return

    async def new_message(self, ip_addr, port, message):
        """process participant new message"""
        log = logging.getLogger(__name__)
        participant = Participant(ip_addr, port, wsocket=None)
        log.debug("%s: new message %s", (ip_addr, port), message)
        try:
            room = self.participant2room[participant]
        except KeyError:
            log.exception("%s: No room, what's happening?", (ip_addr, port))
            return
        else:
            for room_participant in room.participants.copy():
                if room_participant == participant:
                    continue
                # await asyncio.sleep(10)
                await room_participant.send(message)
            room.messages.append(message)
        log.debug(
            "%s: message proceed in room %s (%s #)",
            (ip_addr, port),
            room.name,
            len(room.participants),
        )
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

    async for message in ws:
        if message.type == aiohttp.WSMsgType.TEXT:
            try:
                msg = message.json()
            except json.JSONDecodeError:
                log.exception(
                    "%s: Cannot decode message: %s\nclose client", remote, message
                )
                ws.send_json(
                    system_message(
                        "Json decode error: your message should be json formatted"
                    )
                )
                continue
            else:
                await roomer.new_message(*remote, message=msg)

        elif message.type == aiohttp.WSMsgType.ERROR:
            log.warning(
                "%s: ws connection closed with exception %s", remote, ws.exception()
            )

    roomer.participant_left(*remote)

    return ws


async def ping_participants(roomer):
    log = logging.getLogger(__name__)
    while True:
        for participant in roomer.participant2room.copy():
            if not participant.wsocket.closed:
                continue
            log.debug("%s: socket closed", (participant.ip_addr, participant.port))
            roomer.participant_left(participant.ip_addr, participant.port)
            continue
        await asyncio.sleep(10)


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

    use_ssl = True

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
