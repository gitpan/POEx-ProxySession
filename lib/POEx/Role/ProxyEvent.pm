package POEx::Role::ProxyEvent;
BEGIN {
  $POEx::Role::ProxyEvent::VERSION = '1.102750';
}

#ABSTRACT: Provide a decorator to label events to be proxied

use MooseX::Declare;

role POEx::Role::ProxyEvent with POEx::Role::Event { }
1;


=pod

=head1 NAME

POEx::Role::ProxyEvent - Provide a decorator to label events to be proxied

=head1 VERSION

version 1.102750

=head1 DESCRIPTION

This role is merely a decorator for methods to indicate that the method should
be available for proxy.

=head1 AUTHOR

Nicholas Perez <nperez@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Nicholas Perez.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__
