alias pactl='pactl.pl'
compdef _switchsink pactl.pl
function _switchsink () {
	local -a sinks
	sinks=("${(@f)$(pactl.pl)}")
	_describe 'sinks and streams' sinks
}
