package DB::CouchDB;

use warnings;
use strict;
use JSON -convert_blessed_universally;
use LWP::UserAgent;
use URI;
use Encode;
use URI::Escape;
use HTTP::Headers;
use Carp;
our $VERSION = '0.4.00.1';

=head1 NAME

    DB::CouchDB - A low level perl module for CouchDB

=head1 RATIONALE

After working with a lot several of the CouchDB modules already in CPAN I found
myself dissatisfied with them. Since the API for Couch is so easy I wrote my own
which I find to have an API that better fits a CouchDB Workflow.

=head1 SYNOPSIS

    my $db = DB::CouchDB->new(host => $host,
                              db   => $dbname);
    my $doc = $db->get_doc($docname);
    my $docid = $doc->{_id};

    my $doc_iterator = $db->view('foo/bar', \%view_query_opts);

    while ( my $result = $doc_iterator->next() ) {
        ... #do whatever with the result the view returns
    }

=head1 METHODS

=head2 new(%dbopts)

This is the constructor for the DB::CouchDB object. It expects
a list of name value pairs for the options to the CouchDB database.

=over 4

=item *

Required options: (host => $hostname, db => $database_name);

=item *

Optional options: (port => $db_port)

=back

=cut

sub new {
    my ($class,%opts)  = @_;
    $opts{port} = 5984
      if ( !exists $opts{port} );
    $opts{db} =  uri_escape($opts{db});

    my $obj = {%opts};
    $obj->{json} = JSON->new();
    return bless $obj, $class;
}

=head2 Accessors

=over 4

=item *

host - host name of db

=item *

db - database name

=item *

port - port number of the database server

=item *

json - the JSON object for serialization

=item *

user - the username, if usernames are setup on the db

=item *

password - the password, if usernames are setup on the db

=back

=cut

sub host {
    return shift->{host};
}

sub port {
    return shift->{port};
}

sub db {
    return shift->{db};
}

sub json {
    my $self = shift;
    return $self->{json};
}

sub user {
    return shift->{'user'};
}

sub password {
    return shift->{'password'};
}

=head2 handle_blessed

Turns on or off the JSON's handling of blessed objects.

    $db->handle_blessed(1) #turn on blessed object handling
    $db->handle_blessed() #turn off blessed object handling

=cut

sub handle_blessed {
    my $self = shift;
    my $set  = shift;

    my $json = $self->json();
    if ($set) {
        $json->allow_blessed(1);
        $json->convert_blessed(1);
    }
    else {
        $json->allow_blessed(0);
        $json->convert_blessed(0);
    }
    return $self;
}

sub json_pretty {
    my $self = shift;
    my $enable  = shift;

    my $json = $self->json();
    $json->pretty($enable);
    return $self;
}

sub json_shrink {
    my $self = shift;
    my $enable  = shift;

    my $json = $self->json();
    $json->shrink($enable);
    return $self;
}

=head2 all_dbs

    my $dbs = $db->all_dbs() #returns an arrayref of databases on this server

=cut

sub all_dbs {
    my $self = shift;
    my $args = shift;                   ## do we want to reduce the view?
    my $uri  = $self->_uri_all_dbs();
    if ($args) {
        my $argstring = $self->_valid_view_args($args);
        $uri->query($argstring);
    }
    return $self->_call( GET => $uri );
}

=head2 all_docs

    my $docs = $db->all_docs() #returns a DB::CouchDB::Iterator of
                             #all documents in this database

=cut

sub all_docs {
    my $self = shift;
    my $args = shift;
    my $uri  = $self->_uri_db_docs();
    if ($args) {
        my $argstring = $self->_valid_view_args($args);
        $uri->query($argstring);
    }
    return DB::CouchDB::Iter->new( $self->_call( GET => $uri ) );
}

=head2 db_info

    my $dbinfo = $db->db_info() #returns a DB::CouchDB::Result with the db info

=cut

sub db_info {
    my $self = shift;
    return DB::CouchDB::Result->new( $self->_call( GET => $self->_uri_db() ) );
}

=head2 create_db

Creates the database in the CouchDB server.

    my $result = $db->create_db() #returns a DB::CouchDB::Result object

=cut

sub create_db {
    my $self = shift;
    return DB::CouchDB::Result->new( $self->_call( PUT => $self->_uri_db() ) );
}

=head2 delete_db

deletes the database in the CouchDB server

    my $result = $db->delete_db() #returns a DB::CouchDB::Result object

=cut

sub delete_db {
    my $self = shift;
    return DB::CouchDB::Result->new(
        $self->_call( DELETE => $self->_uri_db() ) );
}

=head2 create_doc

creates a doc in the database. The document will have an automatically assigned
id/name.

    my $result = $db->create_doc($doc) #returns a DB::CouchDB::Result object

=cut

sub create_doc {
    my $self = shift;
    my $doc  = shift;
    my $jdoc = $self->json()->encode($doc);
    return DB::CouchDB::Result->new(
        $self->_call( POST => $self->_uri_db(), $jdoc ) );
}

=head2 bulk_docs

bulk_docs api call

    my $docs = $db->bulk_docs($array_ref_of_docs); #returns an arrayref of
                                                   #outcome of the bulk_docs call.

   From the API page

   CouchDB will return in the response an id and revision for every
   document passed as content to a bulk insert, even for those that
   were just deleted.

   If the _rev does not match the current version of the document,
   then that particular document will not be saved and will be
   reported as a conflict, but this does not prevent other documents
   in the batch from being saved.

   see http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API for more
   information

=cut

sub bulk_docs {
    my $self      = shift;
    my $docref    = shift;
    my $jdocs     = $self->json()->encode( { 'docs' => $docref } );
    my $uri       = $self->_uri_db_bulk_doc();
    my $h = HTTP::Headers->new;
    $h->header('Content-Type' => 'application/json');

    my $array_ref = $self->_call( POST => $uri, $jdocs, $h  );
    return $array_ref;
}

=head2 compact

compact api call

    $db->compact(); # blocks, I guess.  returns null.  This isn't a
    great function to call from this library, but sometimes you need
    it because the db grows without bounds as more and more revisions
    are made to documents

    Anyway, perhaps it is a good thing that this call blocks, because
    the wiki says that _compact calls are a bad idea when lots of
    writes are going on.

=cut

sub compact {
    my $self      = shift;
    my $uri       = $self->_uri_db_compact();
    my $array_ref = $self->_call( POST => $uri );
    return $array_ref;
}

=head2 temp_view

runs a temporary view.

    my $results = $db->temp_view($view_object);

=cut

sub temp_view {
    my $self = shift;
    my $doc  = shift;
    my $jdoc = $self->json()->encode($doc);
    return DB::CouchDB::Iter->new(
        $self->_call( POST => $self->uri_db_temp_view(), $jdoc ) );
}

=head2 create_named_doc

creates a doc in the database, the document will have the id/name you specified

change, pass a hashref now.
before:

    my $result = $db->create_named_doc($doc, $docname) #returns a DB::CouchDB::Result object

now:

    my $result = $db->create_named_doc({'id'=>'somedocid','doc'=>$doc}) #returns a DB::CouchDB::Result object

also, if you stuff the id into the doc as the $doc->{'_id'}, then the
'id' parameter field is optional, as whatever id is stored in the doc
will be used instead.

also, couchdb allows '/' in the _id of a document, but it must be url encoded

note that the response is not a proper couchdb document, in that id
and rev are not _id and _rev fields, but rather 'id' and 'rev'.  Instead you are getting the response to the PUT statement.

=cut

sub create_named_doc {
    my $self = shift;
    my $args = shift;
    my $doc  = $args->{'doc'};
    my $id   = $args->{'id'};
    if ( !$id ) {
        $id = $doc->{'_id'};
    }
    if ( !$id ) {
        return {
            error  => '0',
            reason => 'no id in arguments hash, or in document'
        };
    }
    $id =  uri_escape($id);
    my $jdoc = $self->json()->encode($doc);
    return DB::CouchDB::Result->new(
        $self->_call( PUT => $self->_uri_db_doc($id), $jdoc ) );
}

=head2 update_doc

Updates a doc in the database.

breaking change, pass a hashref now.
before:

    my $result = $db->update_doc($docname, $doc) #returns a DB::CouchDB::Result object

now:

    my $result = $db->update_doc({'id'=>'somedocid','doc'=>$doc}) #returns a DB::CouchDB::Result object

also, if you stuff the id into the doc as the $doc->{'_id'}, then the
'id' parameter field is optional, as whatever id is stored in the doc
will be used instead.

also also, if you want to pass in a suitably modified with changes
DB::CouchDB::Result object, then you first have to make sure you've
called handle_blessed() to allow the json parser to properly handle
blessed objects.

=cut

sub update_doc {
    my $self = shift;
    my $args = shift;
    my $doc  = $args->{'doc'};
    my $id   = $args->{'id'};
    if ( !$id ) {
        $id = $doc->{'_id'};
    }
    if (!$id){
        return DB::CouchDB::Result->new( {error => '0', reason => 'no id in arguments hash, or in document'} );
    }
    my $jdoc = $self->json()->encode($doc);
    return DB::CouchDB::Result->new(
        $self->_call( PUT => $self->_uri_db_doc($id), $jdoc ) );
}

=head2 delete_doc

Deletes a doc in the database. you must supply a rev parameter to
represent the revision of the doc you are updating. If the revision is
not the current revision of the doc the update will fail.

the passed arguments can either be an id and a rev, or else you can
just pass the doc itself, and the id and rev will be extracted from
that.

    my $result = $db->delete_doc($docname, $rev) #returns a DB::CouchDB::Result object

    my $otherresult = $db->delete_doc($doc) #returns a DB::CouchDB::Result object

=cut
sub delete_doc {
    my $self = shift;
    my $doc  = shift;
    my $rev  = shift;
    my $id;
    if(!$rev){
      $rev = $doc->{'_rev'};
      $id = $doc->{'_id'};
    }else{
      $id=$doc;
    }
    $id =  uri_escape($id);
    my $uri  = $self->_uri_db_doc($id);
    $uri->query( 'rev=' . $rev );
    return DB::CouchDB::Result->new( $self->_call( DELETE => $uri ) );
}

=head2 get_doc

Gets a doc in the database.

    my $result = $db->get_doc($docname) #returns a DB::CouchDB::Result object

=cut

sub get_doc {
    my $self = shift;
    my $id  = shift;
    $id = uri_escape($id);
    return DB::CouchDB::Result->new(
        $self->_call( GET => $self->_uri_db_doc($id) ) );
}




=head2 doc_add_attachment

Add an attachment to a doc in the database (or implicitly create the doc)

    my $args = {};
    $args->{'doc'}          =>   $doc,  # required unless passing id and rev
    $args->{'id'}	     =>   $id,  # required if there is no doc or if implicitly creating
    $args->{'rev'}	     =>   $rev, # required if doc exists already
    $args->{'attachment'}   =>   $attachment, #reqired.  Something that can be read in, or just a name to give content that has already been read in
    $args->{'content'} =>   $content to load, if $attachment is not a filename to be read in,
    $args->{'header'} => $header for upload.  If you pass content, and
       it isn't obvious what the media type is from the filen mane
       (attachment parameter, then you should include in the header
       object or hasref passed here the correct Content_Type field set

    my $result = $db->doc_add_attachment($docname,$args) #returns a DB::CouchDB::Result object

=cut

sub doc_add_attachment {
    my $self         = shift;
    my $args         = shift;
    my $doc          = $args->{'doc'};
    my $id           = $args->{'id'};
    my $rev          = $args->{'rev'};
    my $attachment   = $args->{'attachment'};
    my $attach_name   = $args->{'name'} || $attachment;
    my $header = $args->{'header'};
    my $file   = $args->{'file'};
    my $content = $args->{'content'};
    if ( !$id && $doc ) {
        $id = $doc->{'_id'} || $doc->{'id'};
    }
    if ( !$id ) {
        return DB::CouchDB::Result->new(
            {
                error  => '0',
                reason => 'no id in arguments hash, or in document'
            }
        );
    }
    if ( !$rev && $doc ) {
        $rev = $doc->{'_rev'} || $doc->{'rev'};
    }
    my $uri = $self->_uri_db_doc_attachment($id,$attachment);
    if($rev){
      $uri->query( 'rev=' . $rev );
    }
    if(!$content){
      $content=1;
    }
    return DB::CouchDB::Result->new(
        $self->_call_attachment( PUT => $uri, {'file'=>$file, 'attachment'=>$attachment, 'header'=>$header, 'content'=>$content }) );

    # I hate this library right now really really really need to fork
    # and make my own

}

=head2 view

Returns a views results from the database.

    my $rs = $db->view($viewname, \%view_args) #returns a DB::CouchDB::Iter object

=head3 A note about view args:

the view args allow you to constrain and/or window the results that the
view gives back. Some of the ones you will probably want to use are:

    group => "true"      #turn on the reduce portion of your view
    key   => '"keyname"' # only gives back results with a certain key

    #only return results starting at startkey and goint up to endkey
    startkey => '"startkey"',
    endkey   => '"endkey"'

    count => $num  #only returns $num rows
    offset => $num #return starting from $num row

All the values should be valid json encoded.
See http://wiki.apache.org/couchdb/HttpViewApi for more information on the view
parameters

=cut

## TODO: still need to handle windowing on views
sub view {
    my $self = shift;
    my $view = shift;
    my $args = shift;                        ## do we want to reduce the view?
    my $uri  = $self->_uri_db_view($view);
    if ($args) {
        my $argstring = $self->_valid_view_args($args);
        $uri->query($argstring);
    }
    return DB::CouchDB::Iter->new( $self->_call( GET => $uri ) );
}

## from the couchdb api:
### key, startkey, and endkey need to be properly JSON encoded values
### (for example, startkey="string" for a string value).
## so I added json encoding here

sub _valid_view_args {
    my $self = shift;
    my $args = shift;
    my $json = $self->json();
    my $enabled = $json->get_allow_nonref();
    $json->allow_nonref(1);
    my $string;
    my @str_parts = map { join q{=},$_,$json->encode($args->{$_}) } keys %{$args};
    $json->allow_nonref($enabled);
    $string = join q{&}, @str_parts ;
    return $string;
}

sub uri {
    my $self = shift;
    my $u    = URI->new();
    $u->scheme('http');
    $u->host( $self->{host} . ':' . $self->{port} );
    return $u;
}

sub credentials {
    my $self   = shift;
    my $netloc = join q{:}, $self->{host}, $self->{port};
    my $realm  = $self->{'realm'} || 'administrator';
    return ( $netloc, $realm, $self->{'user'}, $self->{'password'} );
}

sub _uri_all_dbs {
    my $self = shift;
    my $uri  = $self->uri();
    $uri->path('/_all_dbs');
    return $uri;
}

sub _uri_db {
    my $self = shift;
    my $db   = $self->{db};
    my $uri  = $self->uri();
    $uri->path( '/' . $db );
    return $uri;
}

sub _uri_db_docs {
    my $self = shift;
    my $db   = $self->{db};
    my $uri  = $self->uri();
    $uri->path( '/' . $db . '/_all_docs' );
    return $uri;
}

sub _uri_db_doc {
    my $self = shift;
    my $db   = $self->{db};
    my $doc  = shift;
    my $uri  = $self->uri();
    $uri->path( '/' . $db . '/' . $doc );
    return $uri;
}

sub _uri_db_bulk_doc {
    my $self = shift;
    my $db   = $self->{db};
    my $uri  = $self->uri();
    $uri->path( '/' . $db . '/_bulk_docs' );
    return $uri;
}

sub _uri_db_compact {
    my $self = shift;
    my $db   = $self->{db};
    my $uri  = $self->uri();
    $uri->path( '/' . $db . '/_compact' );
    return $uri;
}

sub _uri_db_view {
    my $self = shift;
    my $db   = $self->{db};
    my @view = split( /\//, shift, 2 );
    my $uri  = $self->uri();
    $uri->path( '/' . $db . '/_design/' . $view[0] . '/_view/' . $view[1] );
    return $uri;
}

sub uri_db_temp_view {
    my $self = shift;
    my $db   = $self->{db};
    my $uri  = $self->uri();
    $uri->path( '/' . $db . '/_temp_view' );
    return $uri;

}

# put in attachment api here
# Standalone Attachments

sub _uri_db_doc_attachment {
    my $self = shift;
    my $db   = $self->{db};
    my $id  = shift;
    my $attch_name = uri_escape(shift);
    $id = uri_escape($id);
    my $uri  = $self->uri();
    $uri->path( join q{/}, $db ,$id,$attch_name);
    return $uri;
}

sub _process_attachment_file {
  # ripped off from LWP POST processing in Request::Common
  my $self=shift;
  my $file=shift;
  my $header=shift;
  my $content = shift;
  my $h = HTTP::Headers->new(%{$header});
  # my $content;
  if ($file && ! $content) {
    open(my $fh, "<", $file) or Carp::croak("Can't open file $file: $!");
    binmode($fh);
    local($/) = undef; # slurp files
    $content = <$fh>;
    close($fh);
    unless ($h->header("Content-Type")) {
      require LWP::MediaTypes;
      LWP::MediaTypes::guess_media_type($file, $h);
    }
  }
  return [$h,$content];

}


sub _call_attachment {
    my $self    = shift;
    my $method  = shift;
    my $uri     = shift;
    my $args = shift;
    my $attachment = $args->{'attachment'};
    my $header =  $args->{'header'} ;
    my $content = $args->{'content'};
    my $file = $args->{'file'};

    my $req = HTTP::Request->new( $method, $uri );

    if($file){
      my $processed=$self->_process_attachment_file($file,$header);
      $req = HTTP::Request->new( $method, $uri, $processed->[0],$processed->[1]);
    }else{
      my $h=HTTP::Headers->new(%{$header});
      $req = HTTP::Request->new( $method, $uri, $h,$content);
    }
    return $self->_request($req);
}

sub _call {
    my $self    = shift;
    my $method  = shift;
    my $uri     = shift;
    my $content = shift;
    my $header  = shift;
    my $req = HTTP::Request->new( $method, $uri, $header );
    $req->content( Encode::encode( 'utf8', $content ) );
    $req->header( 'Content-Type' => 'application/json' );
    return $self->_request($req);
}

sub _request {
  my $self=shift;
  my $req = shift;
  my $ua = LWP::UserAgent->new();

  if ( $self->{'user'} || $self->{'password'} ) {
    $ua->credentials( $self->credentials() );
  }

  my $return = $ua->request($req);
  my $response = $return->decoded_content( default_charset => 'utf8' );
  my $decoded;
  eval { $decoded = $self->json()->decode($response); };
  if ($@) {
    return { error => $return->code, reason => $response };
  }
  return $decoded;
}

package DB::CouchDB::Iter;

sub new {
    my $self    = shift;
    my $results = shift;
    my $rows    = $results->{rows};

    return bless {
        data     => $rows,
        count    => $results->{total_rows},
        offset   => $results->{offset},
        iter     => mk_iter($rows),
        iter_key => mk_iter( $rows, 'key' ),
        error    => $results->{error},
        reason   => $results->{reason},
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

sub err {
    return shift->{error};
}

sub errstr {
    return shift->{reason};
}

sub next {
    my $self = shift;
    return $self->{iter}->();
}

sub next_key {
    my $self = shift;
    return $self->{iter_key}->();
}

sub next_for_key {
    my $self = shift;
    my $key  = shift;
    my $ph   = $key . "_iter";
    if ( !defined $self->{$ph} ) {
        my $iter = mk_iter(
            $self->{data},
            'value',
            sub {
                my $item = shift;
                return $item
                  if $item->{key} eq $key;
                return;
            }
        );
        $self->{$ph} = $iter;
    }
    return $self->{$ph}->();
}

sub mk_iter {
    my $rows   = shift;
    my $key    = shift || 'value';
    my $filter = shift || sub { return $_ };
    my $mapper = sub {
        my $row = shift;
        return @{ $row->{$key} }
          if ref( $row->{$key} ) eq 'ARRAY' && $key ne 'key';
        return $row->{$key};
    };
    my @list = map { $mapper->($_) } grep { $filter->($_) } @$rows;
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
    my $self   = shift;
    my $result = shift;

    return bless $result, $self;
}

sub err {
    return shift->{error};
}

sub errstr {
    return shift->{reason};
}

1;

__END__

=head1 AUTHOR

Jeremy Wall <jeremy@marzhillstudios.com>

=head1 DEPENDENCIES

=over 4

=item *

L<LWP::UserAgent>

=item *

L<URI>

=item *

L<JSON>

=back

=head1 SEE ALSO

=over 4

=item *

L<DB::CouchDB::Result> - POD for the DB::CouchDB::Result object

=item *

L<DB::CouchDB::Iter> - POD for the DB::CouchDB::Iter object

=item *

L<DB::CouchDB::Schema> - higher level wrapper with some schema handling functionality

=back



=head1 SUBROUTINES/METHODS

=head2 json_pretty

Pass through method to JSON->pretty($enable)



=head2 json_shrink

Pass through method to JSON->shrink($enable)
