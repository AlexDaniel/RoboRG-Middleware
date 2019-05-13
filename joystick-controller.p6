#!/usr/bin/env perl6

unit sub MAIN(
    :$input-device  = ‘/dev/input/js0’,
    :$tilt-scaler = ⅔
);

my $joystick-fh  = open :bin, $input-device;

my $autopilot = True;
my $autopilot-zoom = True;

enum Modes <Slow Normal Fast Fun>;

my $max-value = 32767;

my %scalers = %(
    Slow   => (  800,   70),
    Normal => ( 1000,   70),
    Fast   => ( 2500,  200),
    Fun    => (16000,   70),
);


#| Buttons
multi process($buf where .[6] == 0x01) {
    my $pressed = so $buf[4];
    my $button  =    $buf[7];
    # say ‘button ’, $button, ‘ ’, $pressed;

    if !$pressed and 4 ≤ $button ≤ 7 {
        zoom 0;
        return
    }
    given $button {
        when  5 { zoom-autopilot-off(); zoom +2 }
        when  7 { zoom-autopilot-off(); zoom +5 }
        when  4 { zoom-autopilot-off(); zoom -2 }
        when  6 { zoom-autopilot-off(); zoom -5 }

        when 11 { slow-mode $pressed }
        when 10 { fast-mode $pressed }
        when  9 {  fun-mode $pressed }

        my $value = $pressed ?? 1 !! 0;
        when  3 {  pan -1 × $value * 4, :mode(Slow) }
        when  1 {  pan +1 × $value * 4, :mode(Slow) }
        when  0 { tilt -1 × $value * 2, :mode(Slow) }
        when  2 { tilt +1 × $value * 2, :mode(Slow) }

        when 8  {
            $autopilot = True;
            $autopilot-zoom = True;
        }
    }
}

#| Axis
multi process($buf where .[6] == 0x02) {
    my $axis = $buf[7];
    my int16 $value = ($buf[5] +< 8) + $buf[4];
    my $normalized = $value ÷ $max-value;
    # say ‘axis ’, $axis, ‘ ’, $value;
    if $axis == 0 {
        $autopilot = False;
        pan  $normalized
    } elsif $axis == 3 {
        tilt $normalized
    } elsif $axis == 4 {
        if      $value == -32767 {
            choose-cam 1
        } elsif $value == +32767 {
            choose-cam 2
        }
    } elsif $axis == 5 {
        if      $value == -32767 {
            title-advance -1;
            title-cancel;
        } elsif $value == +32767 {
            title-advance +1;
            title-show;
        }
    }
    #`｢elsif $axis == 4 {
        if $value == -32767 {
            $autopilot = not $autopilot;
        }
    } elsif $axis == 5 {
        if $value == -32767 {
            if $autopilot-zoom {
                zoom-autopilot-off
            } else {
                $autopilot-zoom = True
            }
        }
    }｣
}

#| Don't care
multi process($buf) { }


my $current-mode = Normal;

my $tilt-acc-last = 0;
my $tilt-last = 0;
sub tilt($value = $tilt-last, :$mode = $current-mode) {
    $tilt-last = $value;
    my $scaled = $value × %scalers{$mode}[0] × $tilt-scaler;
    $scaled .= Int;
    my $str = “G0 X$scaled”;
    my $acc = %scalers{$mode}[1];
    if $acc != $tilt-acc-last or (^25).pick == 0 {
        $tilt-acc-last = $acc;
        send “M201 X” ~ %scalers{$mode}[1];
    }
    send $str;
}

my $pan-acc-last = 0;
my $pan-last = 0;
sub pan($value = $pan-last, :$mode = $current-mode) {
    $pan-last = $value;
    my $scaled = $value × %scalers{$mode}[0];
    $scaled .= Int;
    my $str = “G0 Z$scaled”;
    my $acc = %scalers{$mode}[1];
    if $acc != $pan-acc-last or (^25).pick == 0 {
        $pan-acc-last = $acc;
        send “M201 Z” ~ %scalers{$mode}[1];
    }
    send $str;
}


my $zoom-visitors = 0;
sub zoom-autopilot-off() {
    if $autopilot-zoom {
        $zoom-visitors = 0;
        $autopilot-zoom = False;
    }
}
sub zoom(Int() $value) {
    $zoom-visitors += $value ?? +1 !! -1;
    return if !$autopilot-zoom and !$value and $zoom-visitors;
    my $str = “G0 Y$value”;
    send $str;
}


my $slow-mode = False;
my $fast-mode = False;
my  $fun-mode = False;
sub slow-mode($pressed) {
    $slow-mode = $pressed;
    update-mode
}
sub fast-mode($pressed) {
    $fast-mode = $pressed;
    update-mode
}
sub  fun-mode($pressed) {
    return unless $pressed; # latched
    $fun-mode = !$fun-mode;
    update-mode
}

sub update-mode {
    $current-mode = do
    if      $slow-mode {
        Slow
    } elsif $fast-mode {
        Fast
    } elsif  $fun-mode {
        Fun
    } else {
        Normal
    }
    tilt;
    pan;
}


use RoboRG::Middleware;

my $recover-interval = 0.5;
my $channel-control = service-publish ‘manual-controller’,  ‘output’, 4242;
my $channel-visuals = service-publish ‘visuals-controller2’, ‘output’, 4241;

sub send($msg) {
    put ‘output’, $msg; # just for for the terminal
    $channel-control.send: $msg; # send the thing
}
sub send-visuals($msg) {
    put ‘visuals’, $msg; # just for for the terminal
    my $fh = open('joysticklog', :a);
    $fh.put("{now} $msg");
    $fh.close;
    $channel-visuals.send: $msg; # send the thing
}

sub choose-cam($cam-id) {
    send-visuals “cam $cam-id”
}
sub title-advance($difference) {
    send-visuals “title-advance $difference”
}
sub title-show() {
    send-visuals “title-show”
}
sub title-cancel() {
    send-visuals “title-cancel”
}

react {
    whenever Supply.interval: $recover-interval {
        send ‘autopilot-pan ’  ~ +$autopilot;
        send ‘autopilot-zoom ’ ~ +$autopilot-zoom;
    }
    whenever $joystick-fh.Supply(:8size) {
        .note;
        process $_
    }
}
