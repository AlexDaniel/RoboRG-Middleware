#!/usr/bin/env perl6

my $input-device  = ‘/dev/input/js0’;
my $output-device = ‘/dev/ttyUSB0’;
my $baud-rate     = 115200;

my $input-fh  = open :bin, $input-device;
my $output-fh = open :w,   $output-device;

my $autopilot = True;

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
    Slow   => ( 100,   50),
    Normal => (2000,  400),
    Fast   => (3000,  500),
    Fun    => (9000,  800),
    Auto   => (8000,  800), # for software control
);

my $tilt-scaler = 1 / 1.5;


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
        when  7 { zoom +5 }
        when  4 { zoom -2 }
        when  6 { zoom -5 }

        when 11 { slow-mode $pressed }
        when 10 { fast-mode $pressed }
        when  9 {  fun-mode $pressed }

        my $value = $pressed ?? 1 !! 0;
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
    my $normalized = $value ÷ $max-value;
    # say ‘axis ’, $axis, ‘ ’, $value;
    if $axis == 0 {
        $autopilot = False;
        pan  $normalized
    } elsif $axis == 3 {
        tilt $normalized
    } elsif $axis == 4 {
        if $value == -32767 {
            $autopilot = not $autopilot;
        }
    }
}

#| Don't care
multi process($buf) { }


# TODO proper g-code values?


my $current-mode = Normal;

my $tilt-last = 0;
sub tilt($value = $tilt-last, :$mode = $current-mode) {
    $tilt-last = $value;
    my $scaled = $value × %scalers{$mode}[0] × $tilt-scaler;
    $scaled .= Int;
    my $str = “G0 X$scaled”;
    $str = “M201 X” ~ %scalers{$mode}[1] ~ “\n” ~ $str;
    $output-fh.put: $str;
    put $str;
}


my $pan-last = 0;
sub pan($value = $pan-last, :$mode = $current-mode) {
    $pan-last = $value;
    my $scaled = $value × %scalers{$mode}[0];
    $scaled .= Int;
    my $str = “G0 Z$scaled”;
    $str = “M201 Z” ~ %scalers{$mode}[1] ~ “\n” ~ $str;
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

my $dead-delay = 2.0;
my $dead-ticks = 0;

my $iteration-time = 0.1;
my $error = 0;
my $error-prior = 0;
my $integral = 0;
my $KP = 1;
my $KI = 0;
my $KD = 0; # 0.15
my $bias = 0;

my $cap = 1;

my $window = 3;
my @last-errors;

react {
    whenever $input-fh.Supply(:8size) {
         .say;
        process $_
    }
    whenever Supply.interval($dead-delay) {
        $dead-ticks++;
        if $dead-ticks ≥ 2 {
            $error = 0;
        }
    }
    whenever $in {
        $dead-ticks = 0;
        my @words = .words;
        when @words[0] eq ‘Z’ {
            my $current-error = +@words[1];
            @last-errors.unshift: $current-error;
            @last-errors = @last-errors[^$window] if @last-errors > $window;
            # note $error;
            $error = @last-errors.sum / @last-errors;
            #$error = 0 if $error ~~ -5..+5;
        }
        default {
            .say
        }
    }
    whenever Supply.interval($iteration-time) { # PID
        # my $error       = $desired-value – $actual-value;
        $integral       = $integral + ($error * $iteration-time);
        my $derivative  = ($error - $error-prior) / $iteration-time;
        my $output      = $KP * $error + $KI * $integral + $KD * $derivative + $bias;
        $error-prior    = $error;

        #note “error: $error integral: $integral output: $output”;
        $output min= +$cap;
        $output max= -$cap;
        if $autopilot {
            say $output;
            pan $output, :mode(‘Auto’)
        } else {
            $integral = 0
        }
    }
}
