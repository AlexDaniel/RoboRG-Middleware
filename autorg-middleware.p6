#!/usr/bin/env perl6

my $input-device  = ‘/dev/input/js0’;
my $output-device = ‘/dev/ttyUSB0’;
my $baud-rate     = 115200;

my $input-fh  = open :bin, $input-device;
my $output-fh = open :w,   $output-device;

# TODO review these
my @stty-opts = <
   line 0 min 0 time 0
   -brkint -icrnl -imaxbel
   -opost
   -isig -icanon -iexten -echo -echoe -echok -echoctl -echoke
>;

enum Modes <Slow Normal Fast Fun>;

my $max-value = 32767;

my %scalers = %(
    Slow   => 1 ÷ 3000,
    Normal => 1 ÷  200,
    Fast   => 1 ÷   25,
    Fun    => 1 ÷    1,
);

my $tilt-scaler = 1 % 6;


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
        when  5 { zoom +2 }
        when  7 { zoom +4 }
        when  4 { zoom -2 }
        when  6 { zoom -4 }

        when 11 { slow-mode $pressed }
        when 10 { fast-mode $pressed }
        when  9 {  fun-mode $pressed }

        my $value = $pressed ?? $max-value !! 0;
        when  3 {  pan -1 × $value, :mode(Slow) }
        when  1 {  pan +1 × $value, :mode(Slow) }
        when  0 { tilt -1 × $value, :mode(Slow) }
        when  2 { tilt +1 × $value, :mode(Slow) }
    }
}

#| Axis
multi process($buf where .[6] == 0x02) {
    my $axis = $buf[7];
    my int16 $value = ($buf[5] +< 8) + $buf[4];
    # say ‘axis ’, $axis, ‘ ’, $value;
    if $axis == 0 {
        pan  $value
    } elsif $axis == 3 {
        tilt $value
    }
}

#| Don't care
multi process($buf) { }


# TODO proper g-code values?


my $current-mode = Normal;

my $tilt-last = 0;
sub tilt(Int() $value = $tilt-last, :$mode = $current-mode) {
    $tilt-last = $value;
    my $scaled = $value × %scalers{$mode} × $tilt-scaler;
    $scaled .= Int;
    my $str = “G0 X$scaled”;
    $output-fh.put: $str;
    put $str;
}


my $pan-last = 0;
sub pan(Int() $value = $pan-last, :$mode = $current-mode) {
    $pan-last = $value;
    my $scaled = $value × %scalers{$mode};
    $scaled .= Int;
    my $str = “G0 Z$scaled”;
    $output-fh.put: $str;
    put $str;
}


my $zoom-visitors = 0;
sub zoom(Int() $value) {
    $zoom-visitors += $value ?? +1 !! -1;
    return if !$value and $zoom-visitors;;
    my $str = “G0 Y$value”;
    $output-fh.put: $str;
    put $str;
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


run <stty -F>, $output-device, $baud-rate, @stty-opts;

my $in = Channel.new;
start { $in.send: $_ for $*IN.lines }

react {
    whenever $input-fh.Supply(:8size) {
         .say;
        process $_
    }
    whenever $in {
        my @words = .words;
        when @words[0] eq ‘Z’ {
            #say +@words[1];
            pan +@words[1] * 300
        }
        default {
            .say
        }
    }
}
