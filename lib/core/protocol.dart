/// Wire constants for the Sushi Roll protocol (v1).
///
/// Every device runs a small HTTP server. Discovery only has to produce a
/// host + port; everything after that is plain HTTP, which travels happily
/// over Tailscale, VPNs and routed networks where multicast does not.
library;

const int kProtocolVersion = 1;

/// Default TCP port for the HTTP API.
const int kDefaultPort = 47100;

/// UDP multicast group/port used for same-network discovery only.
const String kMulticastGroup = '239.255.71.100';
const int kMulticastPort = 47101;

const String kApiBase = '/sushi/v1';

class Api {
  static const info = '$kApiBase/info';
  static const hello = '$kApiBase/hello';
  static const peers = '$kApiBase/peers';
  static const offer = '$kApiBase/offer';
  static const upload = '$kApiBase/upload';
  static const cancel = '$kApiBase/cancel';
}

/// How long a sender waits for the receiver to tap Accept.
const Duration kOfferTimeout = Duration(minutes: 2);

/// A peer we haven't heard from in this long is shown as offline.
const Duration kPeerStaleAfter = Duration(seconds: 45);
