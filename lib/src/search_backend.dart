library a_la_carte.server.search_backend;

import 'dart:async';

class SearchServiceError {
  final Map result;
  SearchServiceError(Map this.result);
}

abstract class SearchBackend {
  Future<int> get mostRecentSequence;
  Future updateToIndex(Map documents);
/** The updates come through as a json entity as described by CouchDB
 * { "seq":975,
 *   "id":"p:83536f1d-9b52-4d37-af40-2f1060268cdd",
 *   "changes":[{"rev":"12-8c3aa0841c8e275b6e6259beb0f0383a"}],
 *   "deleted":true,
 *   "doc":{
 *     "_id":"83536f1d-9b52-4d37-af40-2f1060268cdd",
 *     "_rev":"12-8c3aa0841c8e275b6e6259beb0f0383a",
 *     "_deleted":true
 *   }
 * }
 * or
 *
 * { "seq":977,
 *   "id":"dc7693dc-f9a4-402b-adfd-6fbb8484b2ef",
 *   "changes":[{"rev":"5-2d62adf827b29c231c2a6272da0e5652"}],
 *   "doc":{
 *     "_id":"dc7693dc-f9a4-402b-adfd-6fbb8484b2ef",
 *     "_rev":"5-2d62adf827b29c231c2a6272da0e5652",
 *     "name":"Hola",
 *     "jobNumber":1110,
 *     "initials":null,
 *     "streetAddress":"123 1st St, Woodland, CA 95695, USA",
 *     "isActive":true,
 *     "account":"a_la_carte",
 *     "type":"project",
 *     "place_id":"ChIJY3cgWPvQhIAR9JmwndFkFL4",
 *     "latitude":38.682141000000001,
 *     "longitude":-121.77093100000002,
 *     "clientName":null,
 *     "geohash":"9qckj1c5g9sz",
 *     "user_data":{
 *       "timestamp":1443127444943,
 *       "user_email":"llamadonica@gmail.com",
 *       "user_full_name":"Adam Stark"
 * } } }
 *
 * The key { "last_seq": xxx } may be ignored or it can be used if needed to
 * update the stream state.
 */
}
