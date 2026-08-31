# usage: vivado -mode batch -source syn/synth.tcl -tclargs <top> [part] [impl]

set top [lindex $argv 0]
if {$top eq ""} {
  error "usage: -tclargs <top> \[part\] \[impl\]"
}

set part [lindex $argv 1]
if {$part eq ""} { set part xc7a35ticsg324-1L }

# third arg "impl" adds place & route, needed for Device view
set do_impl [expr {[lindex $argv 2] eq "impl"}]

set root [file normalize [file join [file dirname [info script]] ..]]
set out  [file join $root syn $top]
file mkdir $out

foreach f [lsort [glob -nocomplain $root/rtl/*.sv]] {
  read_verilog -sv $f
}

# per-block constraints, optional: syn/<top>.xdc
set xdc [file join $root syn $top.xdc]
if {[file exists $xdc]} { read_xdc $xdc }

# out_of_context skips IOB insertion so the report is the block's real cost
synth_design -top $top -part $part \
  -include_dirs [file join $root rtl] \
  -verilog_define SYNTHESIS \
  -mode out_of_context \
  -generic DEPTH=256 \
  -generic WIDTH=32

report_utilization -hierarchical -file $out/util.rpt
report_timing_summary -file $out/timing.rpt
write_checkpoint -force $out/post_synth.dcp

if {$do_impl} {
  opt_design
  place_design
  route_design
  report_utilization -hierarchical -file $out/util_route.rpt
  report_timing_summary -file $out/timing_route.rpt
  write_checkpoint -force $out/post_route.dcp
}

puts "synth: $top on $part -> $out"
