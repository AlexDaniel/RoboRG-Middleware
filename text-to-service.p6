#!/usr/bin/env perl6
use lib ‘/home/alex/git/RoboRG/RoboRG-Middleware/lib’;
use RoboRG::Middleware;

my %channels;

for lines() {
    my ($topic, $message) = .split(‘ ’, 2);
    if %channels{$topic}:!exists {
        %channels{$topic} = service-publish(‘legacy-software-controller’, ‘output’, 4243)
    }
    %channels{$topic}.send: $message;
}
