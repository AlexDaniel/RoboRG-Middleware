# Copyright © 2019
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

use Native::Packing :Endian;
use LANC;

unit class RoboRG::Driver;

has $.baud-rate = 115200;
has $!filehandle;

has $!input-buf  = Buf.new: 0 xx 36;
has $!output-buf = Buf.new: 0 xx (36 - 8); # without LANC
has $.lanc = LANC.new; # LANC buf comes from here

method get-start-sequence    () { $!input-buf.read-uint32: 0 }
method get-pan-speed-current () { $!input-buf.read-int32:  4 }
method get-tilt-speed-current() { $!input-buf.read-int32:  8 }
method get-pan-speed-goal    () { $!input-buf.read-int32: 12 }
method get-tilt-speed-goal   () { $!input-buf.read-int32: 16 }
method get-pan-acceleration  () { $!input-buf.read-int32: 20 }
method get-tilt-acceleration () { $!input-buf.read-int32: 24 }
method get-lanc-data         () { $!input-buf.subbuf:     28, 8 }

# Some of these are not available because you can't do that:
method !set-start-sequence   ($_) { $!output-buf.write-uint32: 0, $_ }
#method set-pan-speed-current ($_) { $!output-buf.write-int32:  4, $_ }
#method set-tilt-speed-current($_) { $!output-buf.write-int32:  8, $_ }
method set-pan-speed-goal    ($_) { $!output-buf.write-int32: 12, $_ }
method set-tilt-speed-goal   ($_) { $!output-buf.write-int32: 16, $_ }
method set-pan-acceleration  ($_) { $!output-buf.write-int32: 20, $_ }
method set-tilt-acceleration ($_) { $!output-buf.write-int32: 24, $_ }
#method set-lanc-data         ($_) { $!input-buf.subbuf:      28, 8 }

method zoom($speed) { $!lanc.zoom: $speed }

submethod TWEAK() {
    self!set-start-sequence(0xAA_AA_AA_AA)
}

method open-device($device = ‘/dev/serial/by-id/usb-RGVID.EU_RoboRG_PTZ_Head-if00’) {
    $!filehandle = open $device, :bin, :rw;

    my @stty-opts = <-echo -echoe -echok -echoctl -echoke>;
    run <stty -F>, $device, $!baud-rate, ‘raw’, @stty-opts;

    start react {
        whenever $!filehandle {
            if .bytes == 36 and .list[^4].all == 0xAA {
                $!input-buf = $_;
                $!lanc.parse-new-datagram: .subbuf: 28, 8;
                self!write;
                CATCH { default { .say; exit }} # TODO come up with something better
            } else {
                # TODO do something useful?
                # dd $_;
            }
        }
    }
}

method !write() {
    $!filehandle.write: $!output-buf;
    $!filehandle.write: $!lanc.get-output-datagram;
}
