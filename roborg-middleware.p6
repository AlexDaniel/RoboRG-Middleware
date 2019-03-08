#!/usr/bin/env perl6

use RoboRG::Middleware;

my $output-device = ‘/dev/ttyUSB0’;
my $baud-rate     = 115200;

my $output-fh = open :w,   $output-device;

my @stty-opts = <
   line 0 min 0 time 0
   -brkint -icrnl -imaxbel
   -opost
   -isig -icanon -iexten -echo -echoe -echok -echoctl -echoke
>;

run <stty -F>, $output-device, $baud-rate, @stty-opts;

my $debug-interval = 0.01;

my $dead-delay = 1.0;
my $dead-ticks = 0;

my $iteration-time = 0.1;
my $current-reading = 0;
# my $last-reading = 0;
my $last-reading-with-decay = 0;
my $error-prior = 0;
my $desired-value = 0;
my $integral = 0;
my $KP = 1.0;
my $KI = 0;
my $KD = 0;
my $bias = 0;

my $cap = 1;

my $window = 10;
my @last-errors = 0;
my $last-manual-pan = 0;
my $last-pan-output = 0;

my $zoom-error = 0;

my $autopilot-pan  = False;
my $autopilot-zoom = False;

my $debug-channel = service-publish ‘middleware’, ‘debug’, 4200;

my @autopilot-scaler = 10000, 110;
my $zoom-scaler = 17;

my $acceptable-window = 0.15;
my $acceptable-ticks = 0; # how many ticks we were in the acceptable range

my $zoom-panic-threshold = 0.5;
my $zoom-panic = -2;

sub is-acceptable($reading) {
    -$acceptable-window < $reading - $desired-value < +$acceptable-window
}

my $current-range = 0;
my @ranges = (
    ((0.30, 0.0, 0.0), *.abs < 0.2),
    ((0.45, 0.0, 0.0), *.abs < 0.3),
    ((0.60, 0.0, 0.0), *.abs < 0.4),
    ((0.70, 0.1, 0.0), *.abs < 0.5),
    ((1.00, 0.2, 0.0), *),
);

sub goto($KP_goal, $KI_goal, $KD_goal) {
    $KP += ($KP_goal - $KP) / 15;
    $KI += ($KI_goal - $KI) / 15;
    $KD += ($KD_goal - $KD) / 15;
    #note $KP;
}

sub send($cmd) {
    #say $cmd;
    $output-fh.put: $cmd;
}

sub dead-sequence($dead-tick) {
    note ‘DEAD SEQUENCE’;
    given $dead-tick {
        when 5 ≤ * ≤ 6 {
            $last-reading-with-decay = -0.2;
            #$zoom-error = -0.05;
        }
        when 13 ≤ * ≤ 16 {
            $last-reading-with-decay = -0.7;
        }
        when 17 ≤ * ≤ 20 {
            $last-reading-with-decay = +0.7;
        }
        when 21 ≤ * ≤ 24 {
            $last-reading-with-decay = -0.7;
        }
        when 25 ≤ * ≤ 28 {
            $last-reading-with-decay = +0.7;
        }
    }
}

react {
    whenever Supply.interval: $debug-interval {
        $debug-channel.send: join ‘;’,
        ($current-reading, $last-reading-with-decay, $desired-value,
         $last-pan-output,
         )#$zoom-error, $last-manual-pan)
    }
    whenever service-subscribe(‘manual-controller’, ‘output’) {
        my $cmd = .body-text;
        if $cmd.starts-with: ‘G0 Z’ {
            $last-manual-pan = +$cmd.split(‘Z’)[1];
        }
        if $cmd.starts-with: ‘autopilot-pan’ {
            my $value = ?+$cmd.words[1];
            #if !$autopilot-pan and $value {
            if $value {
                $output-fh.put: “M201 Z” ~ @autopilot-scaler[1];
            }
            $autopilot-pan = $value;
        } elsif $cmd.starts-with: ‘autopilot-zoom’ {
            $autopilot-zoom = ?+$cmd.words[1]
        } else {
            send $cmd
        }
    }
    whenever Supply.interval: $dead-delay {
        $dead-ticks++;
        if $dead-ticks ≥ 2 {
            # $last-reading = 0;
            $zoom-error = 0;
            $integral = 0;
            # @last-errors = 0;
            $last-reading-with-decay = 0;
            $desired-value = 0;
            dead-sequence($dead-ticks);
        }
    }
    whenever service-subscribe(‘legacy-software-controller’, ‘output’) {
        my $message = .body-text;
        $dead-ticks = 0;
        my @words = $message.words;
        when @words[0] eq ‘Z’ {
            $current-reading = +@words[1];
            my $i = 0;
            for @ranges -> ($coefs, $matcher) {
                if $current-reading ~~ $matcher {
                    $current-range = $i;
                    goto(|$coefs);
                    last;
                }
                $i++;
            }
            if is-acceptable $current-reading {
                $acceptable-ticks++;;
                $current-reading = $desired-value + ($current-reading
                                                     - $desired-value) / $acceptable-ticks;
                $integral /= 2;
                #dd $acceptable-ticks;
                if $acceptable-ticks > 35 {
                    $desired-value = 0;
                }
            } else {
                $acceptable-ticks = 0;
            }
            @last-errors.unshift: $current-reading;
            @last-errors = @last-errors[^$window] if @last-errors > $window;
            # note $error;
            #$last-reading = @last-errors.sum / @last-errors;

            $last-reading-with-decay = (0.7 * $last-reading-with-decay +
                                        0.3 * $current-reading);
            #$KP = $error.abs;
            #$error = 0 if $error ~~ -5..+5;
        }
        when @words[0] eq ‘Y’ {
            my $current-error = +@words[1];
            $zoom-error = 0.9 * $zoom-error + 0.1 * $current-error; # exponential decay
        }
        default {
            note “UNRECOGNIZED INPUT: $message”
        }
    }
    #`｢
    if $bypass {
        whenever Supply.interval($iteration-time) {
            if $autopilot {
                my $output = $error;
                $output min= +$cap;
                $output max= -$cap;
                say $output;
                pan $output, :mode(‘Bypass’)
            }
        }
    } else {｣
        whenever Supply.interval($iteration-time) { # PID
            #my $error       = $desired-value – $actual-value;
            my $error       = $last-reading-with-decay - $desired-value;
            $integral      += $error * $iteration-time;
            my $derivative  = ($error - $error-prior) / $iteration-time;
            my $p = $KP * $error;
            my $i = $KI * $integral;
            my $d = $KD * $derivative;
            my $output   = $p + $i + $d + $bias;
            $error-prior = $error;

            #note “error: $error integral: $integral output: $output”;
            $output min= +$cap;
            $output max= -$cap;
            if -0.05 < $output < +0.05 {
                #$desired-value = 0;
            } elsif $output > +0.4 {
                $desired-value = -0.15;
            } elsif $output < -0.4 {
                $desired-value = +0.15;
            }

            if $autopilot-pan {
                $last-pan-output = $output;
                my $scaled = round($output * @autopilot-scaler[0]);
                my $cmd = “G0 Z$scaled”;
                send $cmd;
            } else {
                $integral = 0
            }

            dd $current-range;
            note ($KP, $KI, $KD).map(*.round(0.001)).join: “\t”;
            note ($p, $i, $d, $integral, $output).map(*.round(0.001)).join: “\t”;
            dd $desired-value;
        }
        whenever Supply.interval($iteration-time * 3) {
            if $autopilot-zoom {
                my $scaled;
                if $last-pan-output.abs > $zoom-panic-threshold { # panic mode
                    note ‘PANIC!’;
                    $scaled = $zoom-panic;
                } else {
                    $scaled = $zoom-error × $zoom-scaler;
                }
                $scaled .= round;
                my $cmd = “G0 Y$scaled”;
                send $cmd;
            }
        }
    #} #｢｣
}
