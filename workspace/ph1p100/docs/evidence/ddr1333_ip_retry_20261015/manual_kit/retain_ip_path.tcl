if {[llength [info commands retain_ip_path]] == 0} {
proc retain_ip_path {path} {
    set root [file normalize {D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/output}]
    set keep [file normalize {D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/_retained}]
    set src [file normalize $path]
    set prefix "[string tolower $root]/"
    if {![string equal -length [string length $prefix] $prefix "[string tolower $src]/"] || [string equal -nocase $src $root]} {
        error "Retention source outside private export: $src"
    }
    if {![file exists $src]} {return}
    # Reject links/junctions along the path before moving any directory.
    set check $src
    foreach boundary [list $root $keep] {
        if {[file type $boundary] eq "link"} {error "Retention boundary link forbidden: $boundary"}
    }
    while {![string equal -nocase $check $root]} {
        if {[file type $check] eq "link"} {error "Retention link forbidden: $check"}
        set parent [file dirname $check]
        if {$parent eq $check} {error "Retention ancestor escaped private export"}
        set check $parent
    }
    set target [file join $keep [string range $src [expr {[string length $root]+1}] end]]
    set index 0
    set dest $target
    while {[file exists $dest]} {incr index;set dest "$target.$index"}
    set dest [file normalize $dest]
    set kp "[string tolower $keep]/"
    if {![string equal -length [string length $kp] $kp "[string tolower $dest]/"]} {
        error "Retention destination outside private scratch: $dest"
    }
    set check [file dirname $dest]
    while {![string equal -nocase $check $keep]} {
        if {[file exists $check] && [file type $check] eq "link"} {error "Retention destination link forbidden: $check"}
        set parent [file dirname $check]
        if {$parent eq $check} {error "Retention destination ancestor escaped private scratch"}
        set check $parent
    }
    file mkdir [file dirname $dest]
    file rename $src $dest
    set f [open [file join $keep retention.log] a]
    puts $f [list $src $dest]
    close $f
}
}
