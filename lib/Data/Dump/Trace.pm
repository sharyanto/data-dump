package Data::Dump::Trace;

$VERSION = "0.01";

# Todo:
#   - prototypes
#     in/out parameters
#     key/value style parameters or return values
#     globals affected ($!)
#   - exception
#   - wrap class
#   - autowrap in list return
#   - don't dump return values
#   - configurable colors
#   - show call depth using indentation
#   - show nested calls sensibly
#   - time calls

use strict;

use base 'Exporter';
our @EXPORT_OK = qw(call mcall wrap autowrap);

use Carp qw(croak);
use overload ();

my %obj_name;
my %autowrap_class;
my %name_count;

sub autowrap {
    while (@_) {
        my $class = shift;
        my $name = shift;
        unless ($name) {
            $name = lc($class);
            $name =~ s/.*:://;
        }
        $name = '$' . $name unless $name =~ /^\$/;
        $autowrap_class{$class} = $name;
    }
}

sub wrap {
    my %arg = @_;
    my $name = $arg{name} || "func";
    my $func = $arg{func};

    return sub {
        call($name, $func, undef, @_);
    } if $func;

    if (my $obj = $arg{obj}) {
        $name = '$' . $name unless $name =~ /^\$/;
        $obj_name{overload::StrVal($obj)} = $name;
        return bless {
            name => $name,
            obj => $obj,
        }, "Data::Dump::Trace::Wrapper";
    }

    croak("Either the 'func' or 'obj' option must be given");
}

sub call {
    my $name = shift;
    my $func = shift;
    my $proto = shift;
    my $fmt = Data::Dump::Trace::Call->new($name, $proto, \@_);
    if (!defined wantarray) {
        $func->(@_);
        return $fmt->return_void(\@_);
    }
    elsif (wantarray) {
        return $fmt->return_list(\@_, $func->(@_));
    }
    else {
        return $fmt->return_scalar(\@_, scalar $func->(@_));
    }
}

sub mcall {
    my $o = shift;
    my $method = shift;
    my $proto = shift;
    my $oname = ref($o) ? $obj_name{overload::StrVal($o)} || "\$o" : $o;
    my $fmt = Data::Dump::Trace::Call->new("$oname->$method", $proto, \@_);
    if (!defined wantarray) {
        $o->$method(@_);
        return $fmt->return_void(\@_);
    }
    elsif (wantarray) {
        return $fmt->return_list(\@_, $o->$method(@_));
    }
    else {
        return $fmt->return_scalar(\@_, scalar $o->$method(@_));
    }
}

package Data::Dump::Trace::Wrapper;

sub AUTOLOAD {
    my $self = shift;
    our $AUTOLOAD;
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
    Data::Dump::Trace::mcall($self->{obj}, $method, undef, @_);
}

package Data::Dump::Trace::Call;

use Term::ANSIColor qw(YELLOW CYAN RESET);
use Data::Dump ();

*_dump = \&Data::Dump::dump;

sub _dumpav {
    return "(" . _dump(@_) . ")" if @_ == 1;
    return _dump(@_);
}

sub _dumpkv {
    return _dumpav(@_) if @_ % 2;
    my %h = @_;
    my $str = _dump(\%h);
    $str =~ s/^\{/(/ && $str =~ s/\}\z/)/;
    return $str;
}

sub new {
    my($class, $name, $proto, $input_args) = @_;
    my $self = bless {
        name => $name,
        proto => $proto,
        input => _dumpav(@$input_args),
    }, $class;
    return $self;
}

sub print_call {
    my $self = shift;
    my $arg = shift;
    print YELLOW, "$self->{name}", RESET, $self->{input};
}

sub return_void {
    my $self = shift;
    my $arg = shift;
    $self->print_call($arg);
    print "\n";
    return;
}

sub return_scalar {
    my $self = shift;
    my $arg = shift;
    $self->print_call($arg);
    my $s = shift;
    if (my $name = $autowrap_class{ref($s)}) {
        $name .= $name_count{$name} if $name_count{$name}++;
        print " ==> ", CYAN, $name, RESET, "\n";
        $s = Data::Dump::Trace::wrap(name => $name, obj => $s);
    }
    else {
        print " ==> ", CYAN, _dump($s), RESET, "\n";
    }
    return $s;
}

sub return_list {
    my $self = shift;
    my $arg = shift;
    $self->print_call($arg);
    print " ==> ", CYAN, _dumpav(@_), RESET, "\n";
    return @_;
}

1;

__END__

=head1 NAME

Data::Dump::Trace - Helpers to trace function and method calls

=head1 SYNOPSIS

  use Data::Dump::Trace qw(autowrap mcall);

  autowrap("LWP::UserAgent" => "ua", "HTTP::Response" => "res");

  use LWP::UserAgent;
  $ua = mcall(LWP::UserAgent => "new");      # instead of LWP::UserAgent->new;
  $ua->get("http://www.example.com")->dump;

=head1 DESCRIPTION

The following functions are provided:

=over

=item autowrap( $class )

=item autowrap( $class => $prefix )

=item autowrap( $class1 => $prefix1,  $class2 => $prefix2, ... )

Register classes whose objects are are automatically wrapped when
returned by one of the call functions below.  If $prefix is provided
it will be used as to name the objects.

=item wrap( name => $str, func => \&func )

=item wrap( name => $str, obj => $obj )

Returns a wrapped function or object.  When a wrapped function is
invoked then a trace is printed as the underlying function is invoked.
When a method on a wrapped object is invoked then a trace is printed
as methods on the underlying objects are invoked.

=item call( $name, \&func, $proto, @ARGS )

Calls the given function with the given arguments.  The trace will use
$name as the name of the function.

The $proto argument is reserved for future extensions.

=item mcall( $class, $method, $proto, @ARGS )

=item mcall( $object, $method, $proto, @ARGS )

Calls the given method with the given arguments.

The $proto argument is reserved for future extensions.

=back

=head1 SEE ALSO

L<Data::Dump>

=head1 AUTHOR

Copyright 2009 Gisle Aas.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
