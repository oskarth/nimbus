#
#                 Stratus
#              (c) Copyright 2018
#       Status Research & Development GmbH
#
#            Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#            MIT license (LICENSE-MIT)

import
  sequtils, options, strutils, parseopt, chronos, json, times,
  nimcrypto/[bcmode, hmac, rijndael, pbkdf2, sha2, sysrand, utils, keccak, hash],
  eth/keys, eth/rlp, eth/p2p, eth/p2p/rlpx_protocols/[whisper_protocol],
  eth/p2p/[discovery, enode, peer_pool], chronicles

proc `$`*(digest: SymKey): string =
  for c in digest: result &= hexChar(c.byte)

const
  # Whisper nodes taken from:
  # https://github.com/status-im/status-react/blob/develop/resources/config/fleets.json
  WhisperNodes* = [
    "enode://9c2b82304d988cd78bf290a09b6f81c6ae89e71f9c0f69c41d21bd5cabbd1019522d5d73d7771ea933adf0727de5e847c89e751bd807ba1f7f6fc3a0cd88d997@47.52.91.239:443",
    "enode://66ba15600cda86009689354c3a77bdf1a97f4f4fb3ab50ffe34dbc904fac561040496828397be18d9744c75881ffc6ac53729ddbd2cdbdadc5f45c400e2622f7@206.189.243.176:443",
    "enode://0440117a5bc67c2908fad94ba29c7b7f2c1536e96a9df950f3265a9566bf3a7306ea8ab5a1f9794a0a641dcb1e4951ce7c093c61c0d255f4ed5d2ed02c8fce23@35.224.15.65:443",
    "enode://a80eb084f6bf3f98bf6a492fd6ba3db636986b17643695f67f543115d93d69920fb72e349e0c617a01544764f09375bb85f452b9c750a892d01d0e627d9c251e@47.89.16.125:443",
    "enode://4ea35352702027984a13274f241a56a47854a7fd4b3ba674a596cff917d3c825506431cf149f9f2312a293bb7c2b1cca55db742027090916d01529fe0729643b@206.189.243.178:443"
  ]

# Don't do this at home, you'll never get rid of ugly globals like this!
var
  node: EthereumNode

proc subscribeChannel(
    channel: string, handler: proc (msg: ReceivedMessage) {.gcsafe.}) =
  var ctx: HMAC[sha256]
  var symKey: SymKey
  discard ctx.pbkdf2(channel, "", 65356, symKey)

  let channelHash = digest(keccak256, channel)
  var topic: array[4, byte]
  for i in 0..<4:
    topic[i] = channelHash.data[i]

  info "Subscribing to channel", channel, topic, symKey

  discard node.subscribeFilter(newFilter(symKey = some(symKey),
                                          topics = @[topic]),
                              handler)

proc handler(msg: ReceivedMessage) {.gcsafe.} =
  try:
    # ["~#c4",["dcasdc","text/plain","~:public-group-user-message",
    #          154604971756901,1546049717568,[
    #             "^ ","~:chat-id","nimbus-test","~:text","dcasdc"]]]
    let
      src =
        if msg.decoded.src.isSome(): $msg.decoded.src.get()
        else: ""
      payload = cast[string](msg.decoded.payload)
      data = parseJson(cast[string](msg.decoded.payload))
      channel = data.elems[1].elems[5].elems[2].str
      time = $fromUnix(data.elems[1].elems[4].num div 1000)
      message = data.elems[1].elems[0].str

    info "adding", full=(cast[string](msg.decoded.payload))
  except:
    notice "no luck parsing", message=getCurrentExceptionMsg()

proc nimbus_start(port: uint16 = 30303) {.exportc.} =
  let address = Address(
    udpPort: port.Port, tcpPort: port.Port, ip: parseIpAddress("0.0.0.0"))

  let keys = newKeyPair()
  node = newEthereumNode(keys, address, 1, nil, addAllCapabilities = false)
  node.addCapability Whisper

  node.protocolState(Whisper).config.powRequirement = 0

  var bootnodes: seq[ENode] = @[]
  for nodeId in WhisperNodes:
    var bootnode: ENode
    discard initENode(nodeId, bootnode)
    bootnodes.add(bootnode)

  asyncCheck node.connectToNetwork(bootnodes, true, true)
  # # main network has mostly non SHH nodes, so we connect directly to SHH nodes
  # for nodeId in WhisperNodes:
  #   var whisperENode: ENode
  #   discard initENode(nodeId, whisperENode)
  #   var whisperNode = newNode(whisperENode)

  #   asyncCheck node.peerPool.connectToNode(whisperNode)

proc nimbus_poll() {.exportc.} =
  poll()

type
  CReceivedMessage = object
    decoded*: ptr byte
    decodedLen*: csize
    timestamp*: uint32
    ttl*: uint32
    topic*: Topic
    pow*: float64
    hash*: Hash

proc nimbus_subscribe(channel: cstring, handler: proc (msg: ptr CReceivedMessage) {.gcsafe, cdecl.}) {.exportc.} =
  proc c_handler(msg: ReceivedMessage) =
    var cmsg = CReceivedMessage(
      decoded: unsafeAddr msg.decoded.payload[0],
      decodedLen: csize msg.decoded.payload.len(),
      timestamp: msg.timestamp
    )

    handler(addr cmsg)

  subscribeChannel($channel, c_handler)
