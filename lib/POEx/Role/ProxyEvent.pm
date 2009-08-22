package POEx::Role::ProxyEvent;
our $VERSION = '0.092340';


#ABSTRACT: Provide a decorator to label events to be proxied

use MooseX::Declare;

role POEx::Role::ProxyEvent with POEx::Role::Event
{
}
1;



=pod

=head1 NAME

POEx::Role::ProxyEvent - Provide a decorator to label events to be proxied

=head1 VERSION

version 0.092340

=head1 DESCRIPTION

This role is merely a decorator for methods to indicate that the method should
be available for proxy.

=head1 AUTHOR

  Nicholas Perez <nperez@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by Nicholas Perez.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut 



__END__
