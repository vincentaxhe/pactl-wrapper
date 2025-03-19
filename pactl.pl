#!/bin/perl
# 使pactl命令显示当前状态，移动源或者切换默认sink等操作更方便。
use strict;
use JSON;
use YAML;
use utf8::all;
use IPC::System::Simple 'system';
use experimental qw(declared_refs);
use Getopt::Std;
getopts("i:m:v:", my \%options);
my $sinksinfo = qx(pactl -f json list sinks 2> /dev/null);
my $inputsinfo = qx(pactl -f json list sink-inputs 2> /dev/null);
my $inputsinfo_plain = qx(pactl list sink-inputs);
chomp(my $defaultsink = qx(pactl get-default-sink));
my @sinksinfo = decode_json($sinksinfo)->@*;
my @inputsinfo = decode_json($inputsinfo)->@*;
# pactl -f json不能输出media.name值为宽字符，但不用json可以输出。
my %inputsnames = $inputsinfo_plain =~ /^Sink Input #(\d+).*?^\s+media\.name = "(.*?)"$/smg;
my (%sinksbyindex, %inputsbyindex, %sinkinfo, %appinfo);

# 指定sink后查找其中的input方法。
sub getvolume(\%){
	my $node = shift;
    my $left_volume = $node->{volume}{'front-left'}{'value_percent'};
    my $right_volume = $node->{volume}{'front-right'}{'value_percent'};
	if ($left_volume eq $right_volume){
		return $left_volume
	}else{
		return "L${left_volume}R${right_volume}"
	}
}

sub getapp{
	my $sink = shift;
	my @inputapps;
	foreach my \%info (@inputsinfo){
		if ($info{sink} eq $sink){
			my $index = $info{index};
			# 使窗口名控制在较短的长度
			my $inputsname = substr($inputsnames{$index}, 0, 10);
			my $medianame = $info{properties}{'media.name'} eq '(null)' ? $inputsname : $info{properties}{'media.name'};
			my @name = ($info{properties}{'application.name'}, $medianame);
			my $name = "'${\(join ' / ', @name)}'";
			# input也有状态，也是为了使输出与sink相似，只能eval值，它本是bless对象
			my $state = eval $info{corked} ? 'CORKED' : 'PLAYING';
			$state .= ',MUTE' if eval $info{mute};
			my $volume = getvolume %info;
			push @inputapps, {sink => $sink, index => $index, name => $name, state => $state, volume => $volume};
			$inputsbyindex{$index} = {name => $name, volume => $volume};
			$appinfo{$index} = \%info;
		}
	}
	return @inputapps;
}
sub formatvolume($){
	$_[0] =~ s/^([+-]?\d+)%?$/\1%/ or die 'volume adjust arg wrong';
}
# 预先全部循环一次，创建哈希结构以备快速提取需要的信息
foreach my \%sink (@sinksinfo){
	my $index = $sink{index};
	my $state = $sink{state};
	$state .= ',DEFAULT' if $sink{name} eq $defaultsink;
	$state .= ',MUTE' if eval $sink{mute};
	my $volume = getvolume %sink;
	my $name = "'${\($sink{properties}{'node.nick'} // $sink{description})}'";
	$sinksbyindex{$index} = {state => $state, name => $name, volume => $volume};
	$sinkinfo{$index} = \%sink;
	# 使apps为空时同时也是undefined。
	if (my @inputapps = getapp($index)){
		$sinksbyindex{$index}->{apps} = \@inputapps
	}
}

# 显示sink或input的信息
if (exists $options{i}){
	my $index = $options{i} or die 'need sink or inputs';
	# 用YAML提供的Dump输出数据结构更易读
	print Dump $index =~ s|\d+/|| ? $appinfo{$index} : $sinkinfo{$index};
	exit;
# sink或input toggle mute
}elsif(exists $options{m}){
	my $index = $options{m} or die 'need sink or inputs';
	if ($index =~ s|\d+/||){
		system 'pactl', 'set-sink-input-mute' , $index, 'toggle';
		print 'toggle input ', $inputsbyindex{$index}->{name}, ' mute', "\n";
	}else{
		system 'pactl', 'set-sink-mute' , $index, 'toggle';
		print 'toggle sink ', $sinksbyindex{$index}->{name}, ' mute', "\n";
	}
	exit;
}elsif(exists $options{v}){
	my $index = $options{v} or die 'need sink or inputs';
	my $adjust = shift // '100%';
	formatvolume $adjust;
	if ($index =~ s|\d+/||){
		system 'pactl', 'set-sink-input-volume' , $index, $adjust;
		print 'set input ', $inputsbyindex{$index}->{name}, ' volume ', $inputsbyindex{$index}->{volume}, ' to ', $adjust, "\n";
	}else{
		system 'pactl', 'set-sink-volume' , $index, $adjust;
		print 'set sink ', $sinksbyindex{$index}->{name}, ' volume ', $sinksbyindex{$index}->{volume}, ' to ', $adjust, "\n";
	}
	exit;
}

# 使得input在前可以有多个，sink最后
unshift @ARGV, pop @ARGV;
my ($sink, @inputs) = @ARGV; # 数组必须在标量后面，数组会吞噬所有值
if (not defined $sink){
	# 当没有参数时，输出为sink input的状态，能够作为补全
	foreach my $index (keys %sinksbyindex){
		my @items = ($index.':', $sinksbyindex{$index}->{state}, $sinksbyindex{$index}->{volume}, $sinksbyindex{$index}->{name});
		printf '%-15s%-20s%-10s%-30s%-1s', @items, "\n";
		if (defined $sinksbyindex{$index}->{apps}){
			foreach my \%app ($sinksbyindex{$index}->{apps}->@*){
				# 带冒号是方便zsh的补全提示，sink/input使sink和相应的input总是排列在一起，
				# 也使得input总是s|\d+/||为真后的结果
				my @items = ("$app{sink}/$app{index}:", $app{state}, $app{volume}, $app{name});
				printf '%-15s%-20s%-10s%-30s%-1s', @items, "\n";
			}
		}
}
}elsif (not @inputs){
	die 'not a valid sink' unless defined $sinksbyindex{$sink};
	system 'pactl', 'set-default-sink', $sink;
	print 'set default sink to ', $sinksbyindex{$sink}->{name}, "\n";
}else{
	foreach my $input (@inputs){
		if ($input =~ s|\d+/||){
			system 'pactl', 'move-sink-input', $input, $sink;
			print 'move input ', $inputsbyindex{$input}->{name}, ' to ', $sinksbyindex{$sink}->{name}, "\n";
		}else{
		# 当sink下有多个input时，写sink就代表了其下的所有input。
			defined $sinksbyindex{$input}->{apps} or die 'no inputs in sink ', $input;
			foreach my \%app ($sinksbyindex{$input}->{apps}->@*){
				system 'pactl', 'move-sink-input', $app{index}, $sink;
				print 'move input ', $app{name}, ' to ', $sinksbyindex{$sink}->{name}, "\n";
			}
		}
	}
}
