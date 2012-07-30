use strict;
use warnings;
use Test::Memory::Cycle;
use Test::More;

use Test::More tests => 1;

my $app = SomeApp->new;
memory_cycle_ok( $app );

	package SomeApp;
	use strict;
	use warnings;
	use base 'Marquee';
	
	sub new {
		my $self = shift->SUPER::new(@_);
		$self->plugin(PlackMiddleware => ['TestFilter2', sub {my $c = shift;1}, {charset => 'Shift_JIS'}]);
		return $self;
	}

package Plack::Middleware::TestFilter2;
use strict;
use warnings;
use base qw( Plack::Middleware );

sub call {
	
	my $self = shift;
	my $res = $self->app->(@_);
	$self->response_cb($res, sub {
		return sub {
		};
		$res;
	});
}

__END__
