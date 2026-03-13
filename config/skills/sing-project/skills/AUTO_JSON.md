# Data Exchange Between Client and Server

## 1. JSON and Type Encoding

When exchanging data between a Sing client application and a Sing HTTP server, various types of data must be exchanged. JSON format is used for these exchanges, which poses the problem of encoding and decoding beyond the data types allowed by [the JSON standard](https://datatracker.ietf.org/doc/html/rfc8259):
- string
- int
- double
- bool
- null
- object (untyped)
- array (untyped items)

For all other data types, there **must** be a shared convention between client and server on how to encode (and thus decode) all other data structures. Example: a date/time can be encoded as a character string in ISO-8601 format or as a number of milliseconds elapsed since a reference date/time, or as...

A convention must therefore exist between client and server. It is necessary but sufficient **only** when the decoder knows with certainty the final type of the data to be decoded. Example: the convention indicates that a date/time is exchanged as a character string in ISO-8601 format; the sender sends a JSON object of type `string` and the decoder, **knowing that a date/time is expected**, decodes the string received.

## 2. Type Information in JSON

If the expected data type is not strictly defined, another mechanism must exist. Example: in Sing, standard search services define a [`SearchOnField`](SEARCHES.md) parameter for each entity field. There are several classes derived from `SearchOnField` that a sender can send (e.g. `SearchEquality`, `SearchNull`, `SearchIn`, etc.). In these cases, to correctly decode the data, it is necessary that the encoder indicates **the real type** of the data sent.


