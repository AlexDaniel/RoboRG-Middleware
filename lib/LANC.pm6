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
unit class LANC;

# Big thanks to http://www.boehmel.de/lanc.htm

# TODO byte7 is 10000000, why?

enum CameraStatus is export (
    stop      => 0x02,
    rec       => 0x04,
    rec-pause => 0x14,
);

enum Mode is export (
    CameraMode  => 0b01,
    PhotoMode   => 0b10,
);

has $!input-buf  = Buf.new(0 xx 8);
has $!output-buf = Buf.new(0 xx 8);

has $.vendor-id; #= Maybe vendor id? Seems to be 0x42 on all my cameras
has $.camera-id; #= Seems to be camera id, but not really

#| Only these guide codes seem to be used:
#| 0x3 | 0x4 | 0xB | 0xE
#| For these guide codes the values are constant:
#| 0x3 0b1111_1111 0b1111_1111
#| 0x4 0b1111_1111 0b1111_1111
#| 0xE 0b0000_0000 0b0000_0000
#| 0xB some data
has @.bytes67 = Buf.new(0, 0) xx 16;

method parse-new-datagram($buf) {
    $!input-buf = $buf;
    my $guide-code = $buf[5] +> 4;

    @!bytes67[$guide-code] = $buf.subbuf: 6, 2;

    if      $buf[2] == 0x99 {
        $!vendor-id = $buf[3]
    } elsif $buf[2] == 0x49 {
        $!camera-id = $buf[3]
    } # can also be 0, which is fine

    if self.is-invalid-code {
        note ‘LANC: INVALID CODE!’;
    }
    self!update-commands;
}

method get-output-datagram() {
    return $!output-buf;
}

method get-status() { CameraStatus($!input-buf[4]) }

method is-invalid-code   { so $!input-buf[5] +& 0b0000_0001 }
method is-rec-protection { so $!input-buf[5] +& 0b0000_0010 }
method is-battery-low    { so $!input-buf[5] +& 0b0000_0100 }
method is-zero-mem       { so $!input-buf[5] +& 0b0000_1000 }


# Commands

has $!command-timeout = 0;

method !update-commands() {
    if $!command-timeout {
        $!command-timeout--
    } else {
        self.raw-command: 0, 0;
    }
}

#| Zoom speed -1 … +1
method zoom($normal-speed) {
    # Per http://www.boehmel.de/lanc.htm:
    # ① 0b0001_1000 – Normal  command to VTR or video camera
    # ② 0b0010_1000 – Special command to        video camera
    # ③ 0b0011_1000 – Special command to VTR
    # ④ 0b0001_1110 – Normal  command to still  video camera
    #
    # There are zooming commands in both ② and ④, and we will use ②.
    my $speed = round $normal-speed * 8;
    my $absolute = abs $speed;
    if $speed == 0 {
        self.raw-command: 0, 0, :250command-timeout;
    } else {
        # send a zoom command to the camera (-8 … +8)
        my $command = (($speed < 0) +< 4) +| (($absolute - 1) +< 1);
        self.special-command: $command, :250command-timeout;
    }
}

method grid-toggle($byte) { self.special-command: 0x21 }

#| currently only -1 and +1 are supported
method focus($speed) {
    self.special-command: $speed > 0 ?? 0x45 !! 0x47;
}

method poweroff() { self.modern-camera-command: 0x03 }

method       special-command($command, :$!command-timeout=25) {
    self.raw-command: 0b0010_1000, $command;
}

method modern-camera-command($command, :$!command-timeout=25) {
    self.raw-command: 0b1101_1000, $command;
}

method raw-command($byte0, $byte1, :$!command-timeout=$!command-timeout) {
    $!output-buf[0] = $byte0;
    $!output-buf[1] = $byte1;
}
