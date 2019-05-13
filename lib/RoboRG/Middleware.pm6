# Copyright © 2018-2019
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use v6.d;
unit module RoboRG::Middleware;

use Cro::ZeroMQ::Message;
use Cro::ZeroMQ::Socket::Pub;
use Cro::ZeroMQ::Socket::Sub;

my $prefix = ‘tcp://’;

#| Publish a service using mDNS
sub service-announce($service, $port, $description,
                    :$service-type=‘_roborg._tcp’) is export {

    my $p = Proc::Async.new(<avahi-publish -s>, $service, $service-type,
                            $port, $description);
    $p.start;
}

#| Discover a service using mDNS
sub service-get($service,
                :$service-type=‘_roborg._tcp’) is export {

    my $p = Proc::Async.new(‘avahi-browse’, $service-type,
                            <--resolve --parsable --no-db-lookup>);
    supply {
        whenever $p.stdout.lines {
            my @parts = .chomp.split: ‘;’;
            if @parts > 8 and @parts[0] eq ‘=’
            and @parts[2] eq ‘IPv4’ and @parts[3] eq $service { # TODO ipv6?
                note “🤖 Found a service $service”;
                emit @parts[7,8] # address and port
            }
        }
        $p.start;
    }
}

#| Create a publisher
sub service-publish($service, $topic, $port, $host=‘0.0.0.0’) is export {
    service-announce($service, $port, ‘RoboRG’); # TODO description
    my $bind  = “$prefix$host:$port”;

    my $pub = Cro::ZeroMQ::Socket::Pub.new: :$bind;


    my $channel = Channel.new;
    $pub.sinker(supply {
        whenever $channel { emit Cro::ZeroMQ::Message.new($topic, ~$_) }
    }).tap;

    return $channel
}

#| Create a subscriber
sub service-subscribe($service, $topic) is export {
    supply {
        whenever service-get($service) -> ($host, $port) {
            my $connect = “$prefix$host:$port”;
            note “🤖 Connecting to $connect”;

            my $sub = Cro::ZeroMQ::Socket::Sub.new(:$connect, subscribe => $topic);
            whenever $sub.incoming {
                emit $_
            }
        }
    }
}
