#!/bin/env raku
use Terminal::UI 'ui';
use Terminal::ANSIColor;

class MySetHash is SetHash {
    method flip($key) {
    	return without $key;
        if self{$key} {
            self.unset($key);
        } else {
            self.set($key);
        }
    }
}
my %selected_sink is MySetHash, my %selected_input is MySetHash;
my (%belong, @work, $counter);
ui.setup: :2panes;
my (\top,\bottom) = ui.panes;
refresh top;
ui.bind('pane', ' ' => 'select');
ui.bind('pane', Enter => 'alert');
ui.bind('pane', u => 'volume_up');
ui.bind('pane', d => 'volume_down');
ui.bind('pane', m => 'toggle_mute');
top.on:
	select => -> :$raw, :%meta {
		$counter++;
		my ($line, $sink, $input, $item) = %meta<line sink input item>;
		%selected_sink.flip($sink);
		%selected_input.flip($input);
		if %selected_sink{$sink} or %selected_input{$input} {
			top.update: :$line, colored($item, 'red'), :%meta;
		} else {
			top.update: :$line, $item, :%meta;
		}
		ui.refresh;
		respond bottom;
	},
	alert => {
		my $str = @work[$counter]<work> // "Nothing to do";
		ui.alert($str);
		with @work[$counter] {
			pactl @work[$counter]<sink>, @work[$counter]<input>
		}
		refresh top;
		respond bottom;
	},
	volume_up => {
		my $bind = 'volume_up';
		pactl %selected_sink.keys.List, %selected_input.keys.List, $bind;
		refresh top;
	},
	volume_down => {
		my $bind = 'volume_down';
		pactl %selected_sink.keys.List, %selected_input.keys.List, $bind;
		refresh top;
	},
	toggle_mute => {
		my $bind = 'toggle_mute';
		pactl %selected_sink.keys.List, %selected_input.keys.List, $bind;
		refresh top;
	}
ui.interact;
ui.shutdown;

sub respond($pane){
	$pane.clear;
	selectsay $pane, "select sink: ", %selected_sink.Str;
	selectsay $pane, "select input: ", %selected_input.Str;
	if %selected_sink.elems == 1 {
		if not %selected_input {
			my $sink = %selected_sink.Str;
			my $work = "set default sink : $sink";
			$pane.put("$work ?? Enter to excute");
			@work[$counter] = { work => $work, sink => $sink };
		} else {
			my @fathers = %selected_input.keys.map({%belong{$_}});
			if @fathers.all ne %selected_sink.Str {
				my $sink = %selected_sink.Str;
				my @inputs = %selected_input.keys.List;
				my $work = "move inputs to sink : @inputs[] -> $sink";
				$pane.put("$work ?? Enter to excute");
				@work[$counter] = { work => $work, sink => $sink, input => @inputs}
			}
		}
	}
}

multi sub pactl(Str $sink, Any) {
	run qqw{pactl set-default-sink $sink};
}

multi sub pactl(Str $sink, List:D $inputs) {
	run qqw{pactl move-sink-input $_  $sink} for @$inputs;
}

multi sub pactl(List $sinks, List $inputs, Str:D $bind) {
	given $bind {
		when 'volume_up' {
			run qqw{pactl set-sink-volume $_ +5%} for @$sinks;
			run qqw{pactl set-sink-input-volume $_ +5%} for @$inputs
		}
		when 'volume_down' {
			run qqw{pactl set-sink-volume $_ -5%} for @$sinks;
			run qqw{pactl set-sink-input-volume $_ -5%} for @$inputs
		}
		when 'toggle_mute' {
			run qqw{pactl set-sink-mute $_ toggle} for @$sinks;
			run qqw{pactl set-sink-input-mute $_ toggle} for @$inputs
		}
	}
}

sub selectsay($pane, $prompt, $str){
	$pane.put: $prompt ~ $str if $str
}

sub refresh($pane){
	$pane.clear;
	init;
	my %items = getsinksinputs;
	for %items.keys.sort.kv -> $line, $key {
		my ($sink, $input, $item) = %items{$key}<sink input item>;
		my $itemstr = (%selected_input{$input} or %selected_sink{$sink}) ?? colored($item, 'red') !! $item;
		$pane.put: $itemstr , meta => %( :$line, :$sink, :$input, :$item);
	}
}
sub getsinksinputs{
	my $out = run 'pactl.pl', :out;
	my %items;
	for $out.out.slurp.lines {
		my $item = $_;
		my $head = $item.words[0].substr(0,*-1);
		my ($sink, $input) = $head.split('/');
		%belong{$input} = $sink if $input;
		$sink = Nil if $input;
		%items{$head} = {:$sink, :$input, :$item};
	}
	return %items;
}
sub init{
	%belong = ();
	@work = ();
}