package Builder::LibXML;
use strict;
use warnings;
use Carp;
use Builder::Utils;
use Builder::XML::Utils;
use XML::LibXML;
use XML::LibXML::SAX::Builder;
our $VERSION = '0.01';

use base qw(Builder::XML);

our $Placeholder;
{
    package Builder::LibXML::Placeholder;
    $Placeholder = bless \my $dummy, __PACKAGE__;

    use overload "." => sub {
        # printf "ref(0)=%s  ref(1)=%s\n", ref($_[0]), ref($_[1]);
        ref($_[1]) eq 'Builder::LibXML::Fragment' ? $_[1] : $Placeholder;
    };

}

{
    package Builder::LibXML::Fragment;

    use overload '""' => 'as_string';

    use overload cmp => sub {
        if ($_[2]) {
            return $_[1] cmp $_[0]->as_string;
        }
        else {
            return $_[0]->as_string cmp $_[1];
        }
    };

    sub new {
        my ($class,%args) = @_;
        return bless {
            document => $args{document},
            pretty   => $args{pretty},
        }, $class;
    }

    sub document {
        my $self = shift;
        return $self->{document};
    }

    sub as_string {
        my $self = shift;
        return $self->{as_string}
            ||= $self->document->toString($self->{pretty});
    }
}

sub AUTOLOAD {
    our $AUTOLOAD;

    my ( $self ) = shift;
    my @args = @_;

    if ( $AUTOLOAD =~ /.*::(.*)/ ) {
        my $elt = $1;
        my $attr = undef;
        
        # sub args get resent as callback
        if ( wantarray ) {
             return sub { $self->$elt( @args ) };
        }
        
        # if first arg is hasharray then its attributes!
        $attr = shift @args  if ref $args[0] eq 'HASH';
        
        if ( ref $args[0] eq 'CODE' ) { 
            $self->__element__( context => 'start', element => $elt, attr => $attr );
            $self->__append__(@args);
            $self->__element__( context => 'end', element => $elt );
            return;
        }
        
        # bog standard element         
        $self->__element__( element => $elt, attr => $attr, text => "@args" );
    }
    
    $self;
}

sub __new__ {
    my ( $class ) = shift;
    my %args = __get_args__( @_ );

    # TODO: handle _output or raise an error

    bless { 
        %args,
        block_id => $args{ _block_id }, 
        stack    => $args{ _stack },
        context  => __build_context__(),
    }, $class;
}

sub __get_args__ {
    my ( %arg ) = @_;
    $arg{ns}      = defined $arg{namespace}      ? $arg{namespace}      : '';
    $arg{attr_ns} = defined $arg{attr_namespace} ? $arg{attr_namespace} : '';
    $arg{attr_ns} = $arg{qualified_attr}         ? $arg{ns}             : $arg{attr_ns};

    $arg{cdata} ||= 0;   
    
    return %arg;
}

sub __sax__ {
    my $self = shift;
    return $self->{sax} ||= do {
        my $sax = XML::LibXML::SAX::Builder->new;
        $sax->start_document;
        $sax;
    };
}

sub __build_context__ {
    my $start = sub {
        my ( $self, $param ) = @_;
        
        $self->__push__(sub {
#            my $ns  = $self->{ ns }
#            my $tag = $param->{ element };
#            if ( $attr_ref->{ _xmlns_ } ) {
#                $sax->start_prefix_mapping({
#                    Prefix => $self->{namespace}, NamespaceURI => $attr_ref->{ _xmlns_ } });
#                $sax_params{NamespaceURI} = $attr_ref->{ _xmlns_ };
#                delete $attr_ref->{ _xmlns_ };
#            }
            $self->__sax__->start_element({ Name => $param->{element}, Attributes => $param->{attr} });
            $self->__inc__;
            
            return $Placeholder;
        });
        
    };

    my $end = sub {
        my ( $self, $param ) = @_;
        $self->__push__(sub { 
            $self->__dec__;
            $self->__sax__->end_element;
            if ($self->__level__ == 0) {
                $self->__sax__->end_document;
                my $result = $self->__sax__->result;
                delete $self->{sax};
                return Builder::LibXML::Fragment->new(
                    document => $result, pretty => $self->{pretty});
            }
            else {
                return $Placeholder;
            }
        });
    };
        
    my $element = sub {
        my ( $self, $param ) = @_;
        $start->($self,$param);
        $self->__push__( sub {
            my $sax = $self->__sax__;
            $sax->start_cdata if $self->{cdata};
            $sax->characters({ Data => $param->{text} });
            $sax->end_cdata if $self->{cdata};
            return $Placeholder;
        });
        $end->($self,$param);
    };

    return {
        start   => $start,
        end     => $end,
        element => $element,
    };
}

sub __append__ {
    my $self = shift;
    for my $inner (@_) {
        if (ref $inner eq 'CODE') {
            $inner->();
        }
        elsif (ref $inner eq 'Builder::LibXML::Fragment') {
            $self->__push__( sub {
                my $sax = $self->__sax__;
                my $dom = $sax->{DOM};  # no accessors :-(
                my $target = $sax->{Parent};
                for my $node ($inner->document->childNodes) {
                    $node = $node->cloneNode(1);
                    $dom->importNode($node);
                    $target->appendChild($node);
                }
                return $Placeholder;
            });
        }
        elsif (ref $inner) {
            $self->__push__( sub { $inner } );
        }
        else {
            $self->__push__( sub {
                my $sax = $self->__sax__;
                $sax->start_cdata if $self->{cdata};
                $sax->characters({ Data => $inner });
                $sax->end_cdata if $self->{cdata};
                return $Placeholder;
            });
        }
    }
}

# alias
sub __say__;
BEGIN { *__say__ = \&__append__ }


######################################################
# methods

# no incremental indention from libxml
sub __tab__           { '' }
sub __end_tab__       { '' }
sub __open_newline__  { '' }
sub __close_newline__ { '' }

sub DESTROY {}

1;

# vim: set et ts=4 sw=4 :

