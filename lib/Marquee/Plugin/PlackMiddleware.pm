package Marquee::Plugin::PlackMiddleware;
use strict;
use warnings;
use Mojo::Asset::File;
use Mojo::ByteStream 'b';
use Mojo::DOM;
use Mojo::Util 'url_escape';
use Pod::Simple::HTML;
use Pod::Simple::Search;
use Mojo::DOM;
use Mojo::Util qw'url_unescape encode decode';
use Mojo::Base 'Marquee::Plugin';
use Mojolicious::Plugin::PlackMiddleware;

### ---
### chunk size
### ---
use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 131072;

{
    no strict 'refs';
    *{__PACKAGE__. '::psgi_env_to_mojo_req'} = \&Mojolicious::Plugin::PlackMiddleware::psgi_env_to_mojo_req;
    *{__PACKAGE__. '::mojo_req_to_psgi_env'} = \&Mojolicious::Plugin::PlackMiddleware::mojo_req_to_psgi_env;
    *{__PACKAGE__. '::psgi_res_to_mojo_res'} = \&Mojolicious::Plugin::PlackMiddleware::psgi_res_to_mojo_res;
    *{__PACKAGE__. '::mojo_res_to_psgi_res'} = \&Mojolicious::Plugin::PlackMiddleware::mojo_res_to_psgi_res;
    *{__PACKAGE__. '::_load_class'} = \&Mojolicious::Plugin::PlackMiddleware::_load_class;
}

sub register {
    my ($self, $app, $mws) = @_;
    
    my $inside_app;
    
    my $plack_app = sub {
        my $env = shift;
        my $c = $env->{'mojo.c'};
        my $tx = $c->tx;
        
        $tx->req(psgi_env_to_mojo_req($env));
        
        if ($env->{'mojo.served'}) {
            my $stash = $c->stash;
            for my $key (grep {$_ =~ qr{^mojo\.}} keys %{$stash}) {
                delete $stash->{$key};
            }
            delete $stash->{'status'};
            my $sever = $tx->res->headers->header('server');
            $tx->res(Mojo::Message::Response->new);
            $tx->res->headers->header('server', $sever);
            $inside_app->();
        } else {
            $inside_app->();
            $env->{'mojo.served'} = 1;
        }
        
        return mojo_res_to_psgi_res($tx->res);
    };
        
    my @mws = reverse @$mws;
    while (scalar @mws) {
        my $args = (ref $mws[0] eq 'HASH') ? shift @mws : undef;
        my $cond = (ref $mws[0] eq 'CODE') ? shift @mws : undef;
        my $e = _load_class(shift @mws, 'Plack::Middleware');
        $plack_app = Mojolicious::Plugin::PlackMiddleware::_Cond->wrap(
            $plack_app,
            condition => $cond,
            builder => sub {$e->wrap($_[0], %$args)},
        );
    }
    
    $app->hook('around_dispatch' => sub {
        $inside_app = shift;
        
        my $c = Marquee->c;
        
        if ($c->tx->req->error) {
            $inside_app->();
            return;
        }
        
        my $plack_env = mojo_req_to_psgi_env($c->tx->req);
        
        local $plack_env->{'mojo.c'} = $c;
        
        local $plack_env->{'psgi.errors'} =
            Mojolicious::Plugin::PlackMiddleware::_EH->new(sub {
                $c->app->log->debug(shift);
            });
        
        $c->tx->res(psgi_res_to_mojo_res($plack_app->($plack_env)));
        
        if (! $plack_env->{'mojo.served'}) {
            $c->served;
        }
    });
}

1;

__END__

=head1 NAME

Mojolicious::Plugin::PlackMiddleware - Plack::Middleware inside Mojolicious

=head1 SYNOPSIS

    # Mojolicious
    
    sub new {
        my $self = shift;
        
        $self->plugin(PlackMiddleware => [
            'MyMiddleware1', 
            'MyMiddleware2', {arg1 => 'some_vale'},
            'MyMiddleware3', $condition_code_ref, 
            'MyMiddleware4', $condition_code_ref, {arg1 => 'some_value'}
        ]);
    }
    
    package Plack::Middleware::MyMiddleware1;
    use strict;
    use warnings;
    use base qw( Plack::Middleware );
    
    sub call {
        my($self, $env) = @_;
        
        # pre-processing $env
        
        my $res = $self->app->($env);
        
        # post-processing $res
        
        return $res;
    }
  
=head1 DESCRIPTION

Marquee::Plugin::PlackMiddleware allows you to enable Plack::Middleware
inside Marquee using around_dispatch hook so that the portability of your
app covers pre/post process too.

It also aimed at those who used to Marquee bundle servers.
Note that if you can run your application on a plack server, there is proper
ways to use middlewares. See L<http://blog.kraih.com/mojolicious-and-plack>.

=head2 OPTIONS

This plugin takes an argument in Array reference which contains some
middlewares. Each middleware can be followed by callback function for
conditional activation, and attributes for middleware.

    my $condition = sub {
        my $c   = shift; # Marquee context
        my $env = shift; # PSGI env
        if (...) {
            return 1; # causes the middleware hooked
        }
    };
    plugin PlackMiddleware => [
        Plack::Middleware::MyMiddleware, $condition, {arg1 => 'some_value'},
    ];

=head1 METHODS

=head2 register

$plugin->register;

Register plugin hooks in L<Marquee> application.

=head2 psgi_env_to_mojo_req

This is a utility method. This is for internal use.

    my $mojo_req = psgi_env_to_mojo_req($psgi_env)

=head2 mojo_req_to_psgi_env

This is a utility method. This is for internal use.

    my $plack_env = mojo_req_to_psgi_env($mojo_req)

=head2 psgi_res_to_mojo_res

This is a utility method. This is for internal use.

    my $mojo_res = psgi_res_to_mojo_res($psgi_res)

=head2 mojo_res_to_psgi_res

This is a utility method. This is for internal use.

    my $psgi_res = mojo_res_to_psgi_res($mojo_res)

=head1 Example

Plack::Middleware::Auth::Basic

    $self->plugin(PlackMiddleware => [
        'Auth::Basic' => sub {shift->req->url =~ qr{^/?path1/}}, {
            authenticator => sub {
                my ($user, $pass) = @_;
                return $user eq 'user1' && $pass eq 'pass';
            }
        },
        'Auth::Basic' => sub {shift->req->url =~ qr{^/?path2/}}, {
            authenticator => sub {
                my ($user, $pass) = @_;
                return $user eq 'user2' && $pass eq 'pass2';
            }
        },
    ]);

Plack::Middleware::ErrorDocument

    $self->plugin('PlackMiddleware', [
        ErrorDocument => {
            500 => "$FindBin::Bin/errors/500.html"
        },
        ErrorDocument => {
            404 => "/errors/404.html",
            subrequest => 1,
        },
        Static => {
            path => qr{^/errors},
            root => $FindBin::Bin
        },
    ]);

Plack::Middleware::JSONP

    $self->plugin('PlackMiddleware', [
        JSONP => {callback_key => 'json.p'},
    ]);

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
