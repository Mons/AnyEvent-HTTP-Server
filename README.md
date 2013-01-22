# Important message

This version of server is almost obsoleted.

New version will be available at http://github.com/Mons/AnyEvent-HTTP-Server-II

Migration is very simple

## What is the reason?

* Current implementation is rather slow (see benchmarks).
* Current implementation have a bit bad app design
* Current implementation have deps, that could be avoided

## What is still better in current?

* New version have no WebSockets support (yet)
* New version have no dispatch actions (static, dir index, etc) (yet)
* New version was written from scratch, so bugs is possible at this stage

## Why name collision?

This module was not yet released to CPAN, and I found it is the best name for AnyEvent-based HTTP server component.

**Sorry for inconvenience**.

I've been trying to make new version compatible with old. But there were performance issues and not so good design

For ex: it is almost impossible to upload really big file (for ex: .iso) using old implementation.

## Benchmarks

Benchmarking tool
	weighttp -c 100 -n 10000 http://localhost:8080/

Example app
	HTTP server on port 8080, which should reply with string "Good"

* AnyEvent::HTTP::Server (current)

	finished in 3 sec, 421 millisec and 143 microsec, **2922** req/s, 278 kbyte/s
   
* Twiggy (v0.1021)

	finished in 1 sec, 630 millisec and 908 microsec, **6131** req/s, 272 kbyte/s

* Starman (--workers 1) (v0.3006)

	finished in 2 sec, 469 millisec and 571 microsec, **4049** req/s, 511 kbyte/s

* Starman (--workers 4) (best for my 4 core)

	finished in 1 sec, 102 millisec and 631 microsec, **9069** req/s, 1161 kbyte/s

* AnyEvent::HTTP::Server-II (1 worker)

	finished in 1 sec, 295 millisec and 127 microsec, **7721** req/s, 912 kbyte/s

* AnyEvent::HTTP::Server-II (4 workers)

	finished in 0 sec, 552 millisec and 381 microsec, **18103** req/s, 2139 kbyte/s
