package DB::CouchDB;

use warnings;
use strict;
use JSON -convert_blessed_universally;
use LWP::UserAgent;
use URI;

$DB::CouchDB::VERSION = 0.2;

=head1 NAME

    DB::CouchDB - An alternative to the Net::CouchDb module

=head1 RATIONALE

Net::CouchDb uses JSON::Any which means handling blessed objects is difficult.
Since the JSON serializer could be any one of a number of modules setting the correct
parameters is difficult and in fact the Net::CouchDb module doesn't allow for this.
DB::CouchDB is intended to allow the modifying the functionality of the serializer
for blessed objects and so on.

DB::CouchDB makes no assumptions about what you will be sending to your db. You don't
have to create special document objects to submit. It will make correct assumptions
as much as possible and allow you to override them as much as possible.

=cut

sub new{
    my $class = shift;
    my %opts = @_;
    $opts{port} = 5984
        if (!exists $opts{port});
    my $obj = {%opts};
    $obj->{json} = JSON->new();
    return bless $obj, $class; 
}

sub host {
    return shift->{host};
}

sub port {
    return shift->{port};
}

sub db {
    return shift->{db};
}

sub all_dbs {
    my $self = shift;
    return DB::CoucnDB::Result->new($self->_call(GET => $self->_uri_all_dbs())); 
}

sub db_info {
    my $self = shift;
    return DB::CoucnDB::Result->new($self->_call(GET => $self->_uri_db()));
}

sub create_db {
    my $self = shift;
    return DB::CoucnDB::Result->new($self->_call(PUT => $self->_uri_db()));
}

sub delete_db {
    my $self = shift;
    return DB::CoucnDB::Result->new($self->_call(DELETE => $self->_uri_db()));
}

sub create_doc {
    my $self = shift;
    my $doc = shift;
    my $jdoc = $self->json()->encode($doc);
    return DB::CoucnDB::Result->new($self->_call(POST => $self->_uri_db(), $jdoc));
}

sub create_named_doc {
    my $self = shift;
    my $doc = shift;
    my $name = shift;
    my $jdoc = $self->json()->encode($doc);
    return DB::CoucnDB::Result->new($self->_call(PUT => $self->_uri_db_doc($name), $jdoc));
}


sub update_doc {
    my $self = shift;
    my $name = shift;
    my $doc  = shift;
    my $jdoc = $self->json()->encode($doc);
    return DB::CoucnDB::Result->new($self->_call(PUT => $self->_uri_db_doc($name), $jdoc));
}

sub delete_doc {
    my $self = shift;
    my $doc = shift;
    my $rev = shift;
    my $uri = $self->_uri_db_doc($doc);
    $uri->query('rev='.$rev);
    return DB::CoucnDB::Result->new($self->_call(DELETE => $uri));
}

sub get_doc {
    my $self = shift;
    my $doc = shift;
    return DB::CoucnDB::Result->new($self->_call(GET => $self->_uri_db_doc($doc)));
}

## TODO: still need to handle windowing on views
sub view {
    my $self = shift;
    my $view = shift;
    my $args = shift; ## do we want to reduce the view?
    my $uri = $self->_uri_db_view($view);
    if ($args) {
        my $argstring = _valid_view_args($args);
        $uri->query($argstring);
    }
    return DB::CouchDB::Iter->new($self->_call(GET => $uri));
}

sub _valid_view_args {
    my $args = shift;
    my $string;
    my @str_parts = map {"$_=$args->{$_}"} keys %$args;
    $string = join('&', @str_parts);

    return $string;
}

sub json {
    my $self = shift;
    return $self->{json};
}

sub handle_blessed {
    my $self = shift;
    my $set  = shift;

    my $json = $self->json();
    if ($set) {
        $json->allow_blessed(1);
        $json->convert_blessed(1);
    } else {
        $json->allow_blessed(0);
        $json->convert_blessed(0);
    }
    return $self;
}

sub uri {
    my $self = shift;
    my $u = URI->new();
    $u->scheme("http");
    $u->host($self->{host}.':'.$self->{port});
    return $u;
}

sub _uri_all_dbs {
    my $self = shift;
    my $uri = $self->uri();
    $uri->path('/_all_dbs');
    return $uri;
}

sub _uri_db {
    my $self = shift;
    my $db = $self->{db};
    my $uri = $self->uri();
    $uri->path('/'.$db);
    return $uri;
}

sub _uri_db_docs {
    my $self = shift;
    my $db = $self->{db};
    my $uri = $self->uri();
    $uri->path('/'.$db.'/_all_docs');
    return $uri;
}

sub _uri_db_doc {
    my $self = shift;
    my $db = $self->{db};
    my $doc = shift;
    my $uri = $self->uri();
    $uri->path('/'.$db.'/'.$doc);
    return $uri;
}

sub _uri_db_bulk_doc {
    my $self = shift;
    my $db = $self->{db};
    my $uri = $self->uri();
    $uri->path('/'.$db.'/_bulk_docs');
    return $uri;
}

sub _uri_db_view {
    my $self = shift;
    my $db = $self->{db};
    my $view = shift;
    my $uri = $self->uri();
    $uri->path('/'.$db.'/_view/'.$view);
    return $uri;
}

sub _call {
    my $self    = shift;
    my $method  = shift;
    my $uri     = shift;
    my $content = shift;

    my $req     = HTTP::Request->new($method, $uri);
    $req->content($content);
         
    my $ua = LWP::UserAgent->new();
    my $response = $ua->request($req)->content();
    my $decoded = $self->json()->decode($response);
    return $decoded;
}

package DB::CouchDB::Iter;

sub new {
    my $self = shift;
    my $results = shift;
    my $rows = $results->{rows};
    
    return bless { data => $rows,
                   count => $results->{total_rows},
                   offset => $results->{offset},
                   iter => mk_iter($rows),
                   error => $results->{error},
                   reason => $results->{reason},
                 }, $self;
}

sub count {
    return shift->{count};
}

sub offset {
    return shift->{offset};
}

sub data {
    return shift->{data};
}

sub next {
   my $self = shift;
   my $key = shift;
   return $self->{iter}->($key); 
}

sub err {
    return shift->{error};
}

sub errstr {
    return shift->{reason};
}

sub mk_iter {
    my $rows = shift;
    my $mapper = sub {
        my $row = shift;
        return @{ $_->{value} }
            if ref($_{value}) eq 'ARRAY';
        return $_->{value};
    };
    my @list = map { $mapper->($_) } @$rows;
    my $index = 0;
    return sub {
        return if $index > $#list;
        my $row = $list[$index];
        $index++;
        return $row;
    };
}

package DB::CouchDB::Result;

sub new {
    my $self = shift;
    my $result = shift;
    
    return bless $result, $self;
}

sub err {
    return shift->{error};
}

sub errstr {
    return shift->{reason};
}


=head1 AUTHOR

Jeremy Wall <jeremy@marzhillstudios.com>

=head1 TODO

- add view creation helpers
- add more robust error handling
- documentation

=cut

1;
