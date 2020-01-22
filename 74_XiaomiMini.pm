#########################################################################
# Modul to extract sensorData from the Xiaomi LYWSD03MMC
# 74_XiaomiLYWSD03MMC.pm
# 2020-01-21 10:37:00 
# Mathias Passow -> Contact -> mathias.passow@me.com
#
# version 0.0.1
#
# changes:
# 2020-01-21 initial alpha, privat testing

#

package main;

use strict;
use warnings;
use POSIX;
use HttpUtils;
use utf8;
use feature						':5.14';

package FHEM::XiaomiMini;

my $missingModul = "";

use GPUtils qw(GP_Import GP_Export);

eval "use Blocking;1" or $missingModul .= "Blocking ";

#use Data::Dumper;          only for Debugging

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          defs
          modules
          Log3
          CommandAttr
          AttrVal
          ReadingsVal
          ReadingsNum
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          InternalTimer
          RemoveInternalTimer
          DoTrigger
          BlockingKill
          BlockingCall
          FmtDateTime
          readingFnAttributes
          makeDeviceName)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      stateRequestTimer2
      )
);

my %CallBatteryAge = (
    '8h'  => 28800,
    '16h' => 57600,
    '24h' => 86400,
    '32h' => 115200,
    '40h' => 144000,
    '48h' => 172800
);

sub Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}    = "FHEM::XiaomiMini::Set";
    $hash->{GetFn}    = "FHEM::XiaomiMini::Get";
    $hash->{DefFn}    = "FHEM::XiaomiMini::Define";
    $hash->{NotifyFn} = "FHEM::XiaomiMini::Notify";
    $hash->{UndefFn}  = "FHEM::XiaomiMini::Undef";
    $hash->{AttrFn}   = "FHEM::XiaomiMini::Attr";
    $hash->{AttrList} =
        "interval "
      . "disable:1 "
      . "disabledForIntervals ";

}

sub Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> XiaomiMini <BTMAC>" if ( @a != 3 );
    return "Cannot define XiaomiMini device. Perl modul ${missingModul}is missing." if ($missingModul);

    my $name = $a[0];
    my $mac  = $a[2];

    $hash->{BTMAC}                       = $mac;
    #$hash->{VERSION}                     = version->parse($VERSION)->normal;
    $hash->{INTERVAL}                    = 300;
    #$hash->{helper}{CallSensDataCounter} = 0;
    #$hash->{helper}{CallBattery}         = 0;
    $hash->{NOTIFYDEV}                   = "global,$name";
    $hash->{loglevel}                    = 4;

    readingsSingleUpdate( $hash, "state", "initialized", 0 );
    CommandAttr( undef, $name . ' room XiaomiMini' ) if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    Log3 $name, 3, "XiaomiMini ($name) - defined with BTMAC $hash->{BTMAC}";

    $modules{XiaomiMini}{defptr}{ $hash->{BTMAC} } = $hash;
    return undef;
}

sub Get($$@) {

    my ( $hash, $name, @aa ) = @_;
    my ( $cmd, @args ) = @aa;
    my $mac  = $hash->{BTMAC};

    Log3 $name, 5, "XiaomiMini name -> $name, cmd -> $cmd, mac -> $mac";

    if ($cmd eq 'sensorData' or $cmd eq 'model' or $cmd eq 'firmware' or $cmd eq 'manufactury') {
        Log3 $name, 4,"Get Mac -> $mac, Name -> $name, Cmd -> $cmd";
        myUtils_LYWSD03MMC_main($mac,$name,$cmd);
        #stateRequest2($hash);
    }
    elsif($cmd eq 'battery' and (CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ) ) )
    {   myUtils_LYWSD03MMC_main($mac,$name,$cmd);
        CallBattery_Timestamp($hash);
    }
    elsif($cmd eq 'battery' and (!CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ) ) )
    {   return "First you have to resetBatteryTimestamp, because your last batterycall is less then " .$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ." seconds in the past";
    }
    elsif ( $cmd eq 'devicename' ) {
        return "usage: devicename" if ( @args != 0 );

    }
    else 
    {   my $list = "";
        # List for the get commands
        $list .= "sensorData:noArg model:noArg firmware:noArg manufactury:noArg battery:noArg ";
        return "Unknown argument $cmd, choose one of $list";
    }

    return undef;
}

sub Set($$@) {

    my ( $hash, $name, @aa ) = @_;
    my ( $cmd, @args ) = @aa;


    if ( $cmd eq 'resetBatteryTimestamp' ) 
    {   return "usage: resetBatteryTimestamp" if ( @args != 0 );
        $hash->{helper}{updateTimeCallBattery} = 0;
        return;
    }
    else 
    {   my $list = "";
        $list .= "resetBatteryTimestamp:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

    return undef;
}

sub Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            Log3 $name, 3, "XiaomiMini ($name) - disabled";
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "XiaomiMini ($name) - enabled";
        }
    }

    elsif ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'" unless ( $attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3 $name, 3, "XiaomiMini ($name) - disabledForIntervals";
            stateRequest2($hash);
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "XiaomiMini ($name) - enabled";
        }
    }
    elsif ( $attrName eq "interval" ) {
        
        if ( $cmd eq "set" ) {
            if ( $attrVal < 120 ) {
                Log3 $name, 3, "XiaomiMini ($name) - interval too small, please use something >= 120 (sec), default is 300 (sec)";
                return "interval too small, please use something >= 120 (sec), default is 300 (sec)";
            }
            else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "XiaomiMini ($name) - set interval to $attrVal";
            }
        }

        elsif ( $cmd eq "del" ) {
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "XiaomiMini ($name) - set interval to default";
        }
    }

    return undef;
}

sub Notify($$) {

    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};
    return stateRequestTimer2($hash) if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    stateRequestTimer2($hash)
      if (
        (
            (
                (
                    grep /^DEFINED.$name$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.disable$/,
                    @{$events}
                    or grep /^ATTR.$name.disable.0$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.interval$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.model$/,
                    @{$events}
                    or grep /^ATTR.$name.interval.[0-9]+/,
                    @{$events}
                )
                and $devname eq 'global'
            )
        )
        and $init_done
        or (
            (
                grep /^INITIALIZED$/,
                @{$events}
                or grep /^REREADCFG$/,
                @{$events}
                or grep /^MODIFIED.$name$/,
                @{$events}
            )
            and $devname eq 'global'
        )
      );
  
    return;
}

sub Undef($$) {

    my ( $hash, $arg ) = @_;

    my $mac  = $hash->{BTMAC};
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    BlockingKill( $hash->{helper}{RUNNING_PID} )
      if ( defined( $hash->{helper}{RUNNING_PID} ) );

    delete( $modules{XiaomiMini}{defptr}{$mac} );
    Log3 $name, 3, "Sub XiaomiMini_Undef ($name) - delete device $name";
    return undef;
}


sub myUtils_LYWSD03MMC_main($$$)
{   my ($mac,$name,$cmd) = @_;
    my $hash = $defs{$name};
    my $arg;
  
    Log3 $name, 4,"myUtils_LYWSD03MMC_main, Mac -> $mac, Name -> $name, Cmd -> $cmd, HASH -> $hash";
    readingsSingleUpdate( $hash, "state", "get sensorData", 1 ) if ($cmd eq 'sensorData');
    readingsSingleUpdate( $hash, "state", "get model", 1 ) if ($cmd eq 'model');
    readingsSingleUpdate( $hash, "state", "get firmware", 1 ) if ($cmd eq 'firmware');
    readingsSingleUpdate( $hash, "state", "get manufactury", 1 ) if ($cmd eq 'manufactury');
    readingsSingleUpdate( $hash, "state", "get battery", 1 ) if ($cmd eq 'battery');
  
    # Set Parameter to execute statement
    $arg = "connect $mac, char-write-req 0x0038 0100, disconnect $mac, exit" if($cmd eq 'sensorData');
    $arg = 'a,exit' if($cmd eq 'firmware' or $cmd eq 'manufactury' or $cmd eq 'model' or $cmd eq 'battery');
  
  
    Log3 $name, 5, "Sub myUtils_LYWSD03MMC_main, Before the call - hash -> $hash, hash-helper -> " .$hash->{helper}{RUNNING_PID};
    
    # NonBlocking Call to run Subroutine
    $hash->{helper}{RUNNING_PID} = BlockingCall(
        "FHEM::XiaomiMini::BluetoothCommands",
        $name . "|" . $mac . "|" . $arg ."|" .$cmd,
        "FHEM::XiaomiMini::BluetoothCommands_Done",
        60,
        "FHEM::XiaomiMini::BluetoothCommands_Aborted",
        $hash
    ) unless ( exists( $hash->{helper}{RUNNING_PID} ));
    Log3 $name, 5, "Sub myUtils_LYWSD03MMC_main, After the call - hash -> $hash, hash-helper -> " .$hash->{helper}{RUNNING_PID};
}


# Script for executing a series of bluetoothctl commands
# ======================================================
#	BluetoothCommands ( <list> );
#		<list> = list of arguments to be submitted by BluetoothCommands;
#
#	Note:	in order to facilitate debugging of additional features
#			  - all display-control character seqences are eliminated,
#			  - nl is eplaced by @

sub BluetoothCommands($) 
{	
    use IPC::Open2;
    use IO::Select;
    #use constant	LAUNCH_TIMEOUT	=>	15;			# timeout before submission of next command (seconds)
	my $timeout = 3;

    my ($string) = @_;
    my ($name, $mac, $arg, $cmd) = split("\\|", $string);

    Log3 $name, 4,"BluetoothCommands, Name -> $name, Mac -> $mac, ARG -> $arg, Cmd -> $cmd";
    my $x_response = '';
    my $in_fid;
    my $out_fid;

    if ($cmd eq 'sensorData'){
        open2 ( $in_fid, $out_fid, 'gatttool -I'.' 2>&1' );
    }
    elsif ($cmd eq 'model') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x03".' 2>&1' );
    }
    elsif ($cmd eq 'firmware') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x4e".' 2>&1' );
    }
    elsif ($cmd eq 'manufactury') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x18".' 2>&1' );
    }
    elsif ($cmd eq 'battery') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x1b".' 2>&1' );
    }
    my $x_select = IO::Select->new ( [$in_fid] );
    my $x_controller = '';
    my $prec_command = '';
    my $next_command;
    my $i = 0;
    my $art = ' ';
    my $temperatur = 0;
    my $humidity = 0;
    my $hex;
    my $model = '';
    my $firmware = '';
    my $manufactury = '';
    my $battery = '';
    my $temp_zaehler = 0;
    my $humi_zaehler = 0;
	my $successful = 0;
	my $attempting = 0;
	my $written = 0;
	my $done = 0;
	my $error = 0;
	my $errorText = ' ';
	my $flg = 0;
	my $save_lastBuffer = 0;
	my $flg_humi = 0;
	my $firstCatch = 0;
    my @ARGV = split(',',$arg);
    my $hash = $defs{$name};

    Log3 $name, 4, "XiaomiMini ARGV -> @ARGV, mac -> $mac, name -> $name, cmd -> $cmd";

    foreach ( @ARGV, 'exit') {
        $next_command = $_;

        # Wait for input sollicitation, loop through action info

        while (1) {
            my $x_buffer = '';

            # Read chunks (unbuffered) and assemble lines
            my $launch_flag = 0;
            do {
                my $x_chunk;
                my @x_ready = $x_select->can_read ($timeout);
                if ( @x_ready == 0 ) 
                {   $launch_flag = 1;
                    last;
                }
                sysread ( $in_fid, $x_chunk , 1 );
                $x_buffer .= $x_chunk;
                $x_buffer =~ s/\r/%/g;
                $x_buffer =~ s/\n/@/g;
                
				# Wenn gatttool einen Fehler geworfen hat, 
				if ($next_command !~ /exit/ and $error == 1)
				{	Log3 $name, 4, "XiaomiMini Error -> $error, Command -> $next_command";
					$launch_flag = 1;
					last;
				}
				elsif ($next_command =~ /exit/ and $error == 1)
				{	Log3 $name, 4, "XiaomiMini ErrorBlock2 -> $error, Command -> $next_command, ErrorText -> $errorText";
					return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|error|$errorText";
				}
				
				if ($x_buffer =~ /@/ and $cmd eq 'sensorData') 
				{	#Log3 $name, 4, "XiaomiMini x_buffer -> $x_buffer";
					my $pos = index($x_buffer,'Connection successful');
					if ($pos != -1 and $successful == 0) 
					{	Log3 $name, 4, "XiaomiMini Connection successful to $mac";
						$successful = 1;
						$timeout = 15;
						$launch_flag = 1;
						last;
					}
					$pos = index($x_buffer,'Attempting');
					if ($pos != -1 and $attempting == 0) 
					{	Log3 $name, 4, "XiaomiMini Attempting to connect to $mac";
						$attempting = 1;
						$timeout = 30;
					}
					$pos = index($x_buffer,'written successful');
					if ($pos != -1 and $written == 0) 
					{	Log3 $name, 4, "XiaomiMini Characteristic value was written successfully to $mac";
						$written = 1;
						$timeout = 15;
					}
					$pos = index($x_buffer,'connect error:');
					my $pos1 = index(substr($x_buffer,$pos),'@');
					if ($pos != -1 and $pos1 != -1 and $attempting == 1) 
					{	Log3 $name, 4, "XiaomiMini connect error to $mac -> " .substr($x_buffer,$pos+15,$pos1-15) ." - Pos = $pos, Pos1 = $pos1 - x_buffer -> $x_buffer";
						$error = 1;
						$errorText = substr($x_buffer,$pos+15,$pos1-15);
						last;
					}
					if ($successful == 1 and $written == 1)
					{	my $pos  = index($x_buffer,'value:');
						my $pos1 = index(substr($x_buffer,$pos),'@');
						if ($pos != -1 and $pos1 != -1) 
						{	my $value = substr($x_buffer,$pos+7,14);
							Log3 $name, 4, "XiaomiMini Value -> $value";
							$temperatur = hex((split(' ',$value))[1] .(split(' ',$value))[0])/100;
							$humidity = hex((split(' ',$value))[2]);
							$done = 1;
							$launch_flag = 1;
							last;
							#return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|ok|$errorText";
						}
					}
					$pos = index($x_buffer,'WARNING');
					if ($pos != -1 and $done == 1) 
					{	Log3 $name, 4, "XiaomiMini Disconnect to $mac";
						return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|ok|$errorText";
					}
				}
				if ($x_buffer =~ /@/ and $cmd eq 'model') 
				{	my $pos = index($x_buffer,'descriptor:');
					if ($pos != -1) 
					{	Log3 $name, 4, "XiaomiMini Angekommen, x_buffer -> $x_buffer";
						$hex = substr($x_buffer,$pos+12);
						$hex =~ s/\s+//g;
						$model = pack('H*',$hex);
						return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|ok|$errorText";
					}
					$pos = index($x_buffer,'error:');
					if ($pos != -1) 
					{	return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|error|$errorText";
					}
                }
				if ($x_buffer =~ /@/ and $cmd eq 'battery') {
                   my $pos = index($x_buffer,'descriptor:');
                   if ($pos != -1) {
                      $hex = substr($x_buffer,$pos+12,2);
                      $hex =~ s/\s+//g;
                      $battery = hex($hex);
                      return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|ok|$errorText";
                   }
                   elsif($pos == -1)
                   {   return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|error|$errorText";
                   }
                }
				if ($x_buffer =~ /@/ and $cmd eq 'firmware') {
                   my $pos = index($x_buffer,'descriptor:');
                   if ($pos != -1) {
                      $hex = substr($x_buffer,$pos+12);
                      $hex =~ s/\s+//g;
                      $firmware = pack('H*',$hex);
                      return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|ok|$errorText";
                   }
                }
                if ($x_buffer =~ /@/ and $cmd eq 'manufactury') {
                   my $pos = index($x_buffer,'descriptor:');
                   if ($pos != -1) {
                      $hex = substr($x_buffer,$pos+12);
                      $hex =~ s/\s+//g;
                      $manufactury = pack('H*',$hex);
                      return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|ok|$errorText";
                   }
                }
            } until ( $x_buffer =~ /^%*[^\[].*#\s+/ );

            if ( $launch_flag )
            {   last;
            }
            $x_buffer =~ s/(\n|\e\[0m|\e\[0;\d+m|\e\[0|\e\[K)//g;
            $x_buffer =~ /^%*(.*)@\[bluetooth/;

            # Assembling of output from bluetoothctl is complete
            #	- loop until all output is seen
            #	- stop looping and wait for timeout:
            #		on error message,
            #		when reception of output stops

            if ( $x_buffer =~ /(.+Invalid.+)\[/ ) {
               $next_command = 'exit';
               $x_response = $1;
            }

            if ( $prec_command eq 'exit' ) {
               last;
            }

        } # while looping through actions, waiting for sollicitation
        if ( $prec_command eq 'exit' ) {last;}
        #print "\n     $next_command  ->\n";
        print $out_fid "$next_command\n";
        $prec_command = $next_command;
    }
    close ( $in_fid );
    close ( $out_fid );
    return "$name|$mac|$arg|$temperatur|$humidity|$model|$firmware|$manufactury|$battery|ok|$errorText";
}

sub BluetoothCommands_Done($) {

    my $string = shift;
    my ($name, $mac, $arg, $temperatur, $humidity, $model, $firmware, $manufactury, $battery, $error, $errorText) = split( "\\|", $string );
    my $hash = $defs{$name};

    if ($error eq 'ok')
    {   readingsSingleUpdate($hash, "temperature", $temperatur, 1) if ($temperatur != 0);
        Log3 $name, 3,"BluetoothCommands_Done ($name) - temperatur -> $temperatur";
        readingsSingleUpdate($hash, "humidity", $humidity, 1) if ($humidity != 0);
        Log3 $name, 3,"BluetoothCommands_Done ($name) - humidity -> $humidity";
        readingsSingleUpdate($hash, "state", 'T: ' . ReadingsVal( $name, 'temperature', 0 ) . ' H: ' . ReadingsVal( $name, 'humidity', 0 ), 1);
        Log3 $name, 3,"BluetoothCommands_Done ($name) - state -> " .'T: ' . ReadingsVal( $name, 'temperature', 0 ) . ' H: ' . ReadingsVal( $name, 'humidity', 0 );
        readingsSingleUpdate($hash, "model", $model, 1) if ($model ne '');
        readingsSingleUpdate($hash, "firmware", $firmware, 1) if ($firmware ne '');
        readingsSingleUpdate($hash, "manufactury", $manufactury, 1) if ($manufactury ne '');
        if ($battery ne '')
           {   readingsSingleUpdate($hash, "batteryPercent", $battery, 1);
           if ($battery > 15)
           {   readingsSingleUpdate($hash, "battery", "ok", 1);
           }
           elsif ($battery <= 15)
           {   readingsSingleUpdate($hash, "battery", "low", 1);
           }
           CallBattery_Timestamp($hash);
        }
    }
    elsif($error eq 'error')
    {   readingsSingleUpdate($hash, "state", "$errorText", 1);
	    if ( ReadingsVal( $name, 'model', 'none' ) eq 'none' )
        {   readingsSingleUpdate( $hash, "state", "get model first", 1 );
        }
    }
    delete( $hash->{helper}{RUNNING_PID} );

    Log3 $name, 5,"BluetoothCommands ($name) - BluetoothCommands: Helper is disabled. Stop processing"
}

sub BluetoothCommands_Aborted($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my %readings;

    delete( $hash->{helper}{RUNNING_PID} );
    readingsSingleUpdate( $hash, "state", "unreachable", 1 );
    readingsSingleUpdate( $hash, "state", "aborted", 1 );

    #$readings{'lastGattError'} = 'The BlockingCall Process terminated unexpectedly. Timedout';
    
    Log3 $name, 4, "XiaomiMini ($name) - BluetoothCommands_Aborted: The BlockingCall Process terminated unexpectedly. Timedout";
}

sub stateRequestTimer2($) {

    my ($hash) = @_;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    stateRequest2($hash);

    InternalTimer( gettimeofday() + $hash->{INTERVAL} + int( rand(60) ), "XiaomiMini_stateRequestTimer2", $hash );

    Log3 $name, 4, "XiaomiMini ($name) - stateRequestTimer2: Call Request Timer";
}

sub stateRequest2($) 
{   my ($hash) = @_;
    my $name = $hash->{NAME};
    my $mac = $hash->{BTMAC};
    my %readings;

       if ( !IsDisabled($name) ) {
            if (ReadingsVal( $name, 'model', '' ) =~ /LYWSD03MMC/)
            {   if (CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ) )
                {   myUtils_LYWSD03MMC_main($mac,$name,'battery');
                }
                else
                {   myUtils_LYWSD03MMC_main($mac,$name,'sensorData');
                }
            }
            elsif ( ReadingsVal( $name, 'model', 'none' ) eq 'none' )
            {   readingsSingleUpdate( $hash, "state", "get model first", 1 );
            }
       }
}

## Routinen damit Firmware und Batterie nur alle X male statt immer aufgerufen wird
sub CallBattery_Timestamp($) 
{   my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{helper}{updateTimeCallBattery} = gettimeofday();    # in seconds since the epoch
    $hash->{helper}{updateTimestampCallBattery} = FmtDateTime( gettimeofday() );
    Log3 $name, 3, "CallBattery_Timestamp - hash -> " .$hash->{helper}{updateTimeCallBattery} ." und " .$hash->{helper}{updateTimestampCallBattery};
}

sub CallBattery_UpdateTimeAge($) 
{   my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{helper}{updateTimeCallBattery} = 0 if ( not defined( $hash->{helper}{updateTimeCallBattery} ) );
    my $UpdateTimeAge = gettimeofday() - $hash->{helper}{updateTimeCallBattery};
    Log3 $name, 3, "CallBattery_UpdateTimeAge - UpdateTimeAge -> $UpdateTimeAge";
    return $UpdateTimeAge;
}


sub CallBattery_IsUpdateTimeAgeToOld($$) 
{   my ( $hash, $maxAge ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 3, "CallBattery_IsUpdateTimeAgeToOld - hash -> $hash, maxAge -> $maxAge";
    return ( CallBattery_UpdateTimeAge($hash) > $maxAge ? 1 : 0 );
}

1;
