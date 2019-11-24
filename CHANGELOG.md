
## [Unreleased]

## [6.2.7-0] - 24/11/2019

- Add support for protocol version 620

## [6.1.8-0] - 25/06/2019

- Add support for protocol version 610

## [6.0.15-1] - 23/11/2018

### New
- FDB.Transaction.set_versionstamped_value/4

### Breaking
- FDB.Transaction.set_versionstamped_key/4 now only works with server version 5.2 or greater

## 5.1.7-7 - 21/09/2018

### New
- FDB.Transaction.set_versionstamped_key/4

### Breaking
- The return type of FDB.Transaction.get_versionstamp_q/1 changed from
  Future of type binary to FDB.Versionstamp.t
