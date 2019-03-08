#!/usr/bin/env perl6

use RoboRG::Middleware;

react {
    whenever service-subscribe(‘middleware’, ‘debug’) {
        put .body-text;
        $*OUT.flush;
    }
}
