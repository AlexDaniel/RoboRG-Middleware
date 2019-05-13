#!/usr/bin/env perl6
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

use RoboRG::Middleware;

use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
use Cro::WebSocket::Handler;
use Cro::WebSocket::Message;

unit sub MAIN(IO() $names-file);

my $name-channel = Supplier.new;

my $app = route {
    get -> 'visuals' {
        web-socket -> $incoming {
            note ‘Connected!’;
            supply {
                whenever $incoming -> $message {
                }
                whenever $name-channel -> $name {
                    emit $name;
                }
            }
        }
    }
}

my $http-server = Cro::HTTP::Server.new(port => 8765, application => $app);
$http-server.start;
END .stop with $http-server;


my $index = 0;
my $name = ‘’;

sub set-index($id) {
    $index = $id;
    my @names = $names-file.slurp.lines;
    $index max= 0;
    $index min= @names - 1;
    $name = @names[$index];
    my $next = @names[$index+1] || ‘’;
    note “$index (next: $next)”;
}

my $stdin = Channel.new;
start for lines() { $stdin.send: $_ }

my $ignore = 0;

react {
    whenever service-subscribe(‘visuals-controller2’, ‘output’) {
        #next if $ignore++ %% 2;
        my @words = .body-text.words;
        given @words[0] {
            when ‘title-advance’ {
                set-index($index += +@words[1]);
            }
            when ‘title-show’ {
                note $name;
                $name-channel.emit: $name;
            }
            when ‘title-cancel’ {
                $name-channel.emit: ‘CANCEL’;
            }
            when ‘cam’ {
                $ = run <xdotool key>, ‘F2’ ~ @words[1];
                True
            }
        }
    }
    whenever $stdin {
        my $id = +$_;
        next unless $id;
        set-index $id;
    }
}
