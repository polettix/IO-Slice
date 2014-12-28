package IO::Slice;

# ABSTRACT: restrict reads to a range in a file
# Strongly inspired to IO::String 1.08 by Gisle Aas

use strict;
use warnings;
use English qw< -no_match_vars >;
use Symbol ();
use Fcntl qw< :seek >;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;

sub new {
   my $package = shift;
   my $efh = Symbol::gensym();
   my $self = tie *$efh, $package;
   $self->open(@_);
   return $efh;
}

sub TIEHANDLE {
   DEBUG "TIEHANDLE(@_)";
   my $package = shift;
   my $self = bless {}, $package;
   return $self;
}

sub DESTROY {
   DEBUG "DESTROY(@_)";
}

sub open {
   my $self = shift;
   my %args = ref($_[0]) ? %{$_[0]} : @_;

   $self->close();

   # mandatory features
   for my $mandatory (qw< offset length >) {
      LOGCROAK "open(): missing mandatory feature $mandatory"
         unless defined $args{$mandatory};
      $self->{$mandatory} = $args{$mandatory};
   }

   # optional/conditional features
   $self->{filename} = $args{filename} // '*undefined*';

   # underlying filehandle
   if ($args{fh}) {
      $self->{fh} = $args{fh};
   }
   else {
      LOGCROAK "open(): either fh or filename MUST be provided"
         unless exists $args{filename};
      open my $fh, '<:raw', $args{filename}
         or LOGCROAK "open('$args{filename}'): $OS_ERROR";
      $self->{fh} = $fh;
   }

   $self->{position} = 0;

   return $self; # been there, done that
}

sub close {
   my $self = shift;
   %$self = ();
   return 1;
}

sub openend {
   my $self = shift;
   return exists $self->{fh};
}

sub binmode {
   my $self = shift;
   return ! scalar @_;
}

sub getc {
   my $self = shift;
   my $buf;
   return $buf if $self->read($buf, 1);
   return undef;
}

sub ungetc {
   my $self = shift;
   $self->pos($self->{position} - 1);
   return 1;
}

sub eof {
   my $self = shift;
   return $self->{position} >= $self->{length};
}

sub pos {
   my $self = shift;
   my $retval = $self->{position};
   if (@_) {
      my $newpos = shift;
      $newpos ||= 0;
      $newpos = 0 if $newpos !~ m{\A\d+\z}mxs;
      $newpos += 0; # make it a "normal" non-negative integer
      $newpos = $self->{length} if $newpos > $self->{length};
      $self->{position} = $newpos;
   }
   return $retval;
}


sub seek {
   my ($self, $offset, $whence) = @_;

   $whence = '*undefined*' unless defined $whence;
   if ($whence == SEEK_SET) {
      $self->pos($offset);
   }
   elsif ($whence == SEEK_CUR) {
      $self->pos($self->{position} + $offset);
   }
   elsif ($whence == SEEK_END) {
      $self->pos($self->{length} + $offset);
   }
   else {
      LOGCROAK "seek(): whence value $whence is not valid";
   }

   return 1;
}

sub tell { return shift->{position} }

sub do_read {
   my ($self, $count) = @_;
   my $buf;
   defined (my $nread = $self->read($buf, $count)) or return;
   return $buf;
}

sub getline {
   my $self = shift;
   return if $self->{position} >= $self->{length};

   return $self->do_read($self->{length} - $self->{position})
      unless defined $INPUT_RECORD_SEPARATOR; # slurp mode

   my $chunk_size = 100;
   if (! length $INPUT_RECORD_SEPARATOR) { # paragraph mode
      return $self->_conditioned_getstuff(sub {
         my $idx = CORE::index $_[0], "\n\n";
         return if $idx < 0;
         my $nreturn = ++$idx;
         my $buflen = length $_[0];
         ++$idx;
         ++$idx while ($idx < $buflen) && (substr($_[0], $idx, 1) eq "\n");
         return ($nreturn, $idx);
      });
   }

   # look for $INPUT_RECORD_SEPARATOR, precisely
   return $self->_conditioned_getstuff(sub {
      my $idx = CORE::index $_[0], $INPUT_RECORD_SEPARATOR;
      return if $idx < 0;
      my $n = $idx + length($INPUT_RECORD_SEPARATOR);
      return ($n, $n);
   });
}

sub _conditioned_getstuff {
   my ($self, $condition, $chunk_size) = @_;
   $chunk_size ||= 100;
   my $initial_position = $self->{position};
   my $buffer;
   while ($self->{position} < $self->{length}) {
      my $chunk = $self->do_read($chunk_size);
      if (! $chunk) {
         $self->{position} = $initial_position;
         return;
      }
      $buffer = defined($buffer) ? $buffer . $chunk : $chunk;
      if (my ($nreturn, $ndelete) = $condition->($buffer)) {
         $buffer = substr $buffer, 0, $nreturn;
         $self->pos($initial_position + $ndelete);
         return $buffer;
      }
   }
   return $buffer;
}

sub getlines {
   LOGCROAK "getlines is only valid in list context"
      unless wantarray();
   my $self = shift;
   my ($line, @lines);
   push @lines, $line while defined($line = $self->getline());
   return @lines;
}

sub READLINE {
   goto &getlines if wantarray();
   goto &getline;
}

# read: set $buffer to undef is errors
sub read {
   my $self = shift;
   my $bufref = \shift;
   my $length = shift;

   my $position = $self->{position};
   my $data_length = $self->{length};
   return if $position >= $data_length;

   my $fh = $self->{fh};
   CORE::seek $fh, ($self->{offset} + $position), SEEK_SET
      or return;

   my $available = $data_length - $position;
   $length = $available if $length > $available;

   defined (my $nread = read $fh, $$bufref, $length, @_)
      or return;
   $self->pos($position + $nread);
   return $nread;
}


sub stat {
   my $self = shift;
   return unless $self->opened();
   return 1 unless wantarray();
   my $length = $self->{length};
   return (
      undef, undef,  # dev, ino
      0666,          # filemode
      1,             # links
      $>,            # user id
      $),            # group id
      undef,         # device id
      $length,       # size
      undef,         # atime
      undef,         # mtime
      undef,         # ctime
      512,           # blksize
      int(($length + 511) / 512)  # blocks
   ); 
}

{
   no strict 'refs';
   no warnings 'once';
   my $nothing = sub { return };
   *sysseek = \&seek;
   *print = $nothing;
   *sysread = \&read;
   *printflush = $nothing;
   *printf = $nothing;
   *fileno = $nothing;
   *error  = $nothing;
   *clearerr = $nothing;
   *sync = $nothing;
   *write = $nothing;
   *setbuf = $nothing;
   *setvbuf = $nothing;
   *untaint = $nothing;
   *autoflush = $nothing;
   *fcntl = $nothing;
   *ioctl = $nothing;
   *input_line_number = $nothing;
   *write = $nothing;

   *GETC = \&getc;
   *PRINT = $nothing;
   *PRINTF = $nothing;
   *READ = \&read;
   *WRITE = $nothing;
   *SEEK = \&seek;
   *TELL = \&tell;
   *EOF  = \&eof;
   *CLOSE = \&close;
   *BINMODE = \&binmode;
   *FILENO = $nothing;
}

1;
__END__
