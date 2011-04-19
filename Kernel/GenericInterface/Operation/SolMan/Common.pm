# --
# Kernel/GenericInterface/Operation/SolMan/Common.pm - SolMan common operation functions
# Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
# --
# $Id: Common.pm,v 1.23 2011-04-19 05:14:19 sb Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::SolMan::Common;

use strict;
use warnings;

use MIME::Base64();
use Kernel::System::VariableCheck qw(IsHashRefWithData IsStringWithData);

use Kernel::System::Ticket;
use Kernel::System::CustomerUser;
use Kernel::System::User;
use Kernel::System::GenericInterface::Webservice;

use vars qw(@ISA $VERSION);
$VERSION = qw($Revision: 1.23 $) [1];

=head1 NAME

Kernel::GenericInterface::Operation::SolMan::Common - common operation functions

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Time;
    use Kernel::System::Main;
    use Kernel::System::DB;
    use Kernel::GenericInterface::Operation::SolMan::Common;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $TimeObject = Kernel::System::Time->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $SolManCommonObject = Kernel::GenericInterface::Operation::SolMan::Common->new(
        ConfigObject       => $ConfigObject,
        LogObject          => $LogObject,
        DBObject           => $DBObject,
        MainObject         => $MainObject,
        TimeObject         => $TimeObject,
        EncodeObject       => $EncodeObject,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (
        qw( DebuggerObject MainObject TimeObject ConfigObject LogObject DBObject EncodeObject WebserviceID)
        )
    {

        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{TicketObject}       = Kernel::System::Ticket->new( %{$Self} );
    $Self->{CustomerUserObject} = Kernel::System::CustomerUser->new( %{$Self} );
    $Self->{UserObject}         = Kernel::System::User->new( %{$Self} );
    $Self->{WebserviceObject}   = Kernel::System::GenericInterface::Webservice->new( %{$Self} );

    $Self->{Webservice} = $Self->{WebserviceObject}->WebserviceGet(
        ID => $Param{WebserviceID},
    );

    if ( !IsHashRefWithData( $Self->{Webservice} ) ) {
        return $Self->_ReturnError(
            ErrorCode => 9,
            ErrorMessage =>
                'Could not determine Webservice configuration'
                . ' in Kernel::GenericInterface::Operation::SolMan::Common::new()',
        );
    }

    return $Self;
}

=item TicketSync()

Create/Update a local ticket.

    my $Result = $OperationObject->TicketSync(
        Operation => 'ReplicateIncident', # ReplicateIncident, AddInfo or CloseIncident
        Data => {
            IctAdditionalInfos => {},
            IctAttachments     => {},
            IctHead            => {},
            IctId              => '',     # type="n0:char32", only for ReplicateIncident
            IctPersons         => {},
            IctSapNotes        => {},
            IctSolutions       => {},
            IctStatements      => {},
            IctTimestamp       => '',     # type="n0:decimal15.0", only for ReplicateIncident
            IctUrls            => {},
        },
    );

    $Result = {
        Success      => 1,                                # 0 or 1
        ErrorMessage => '',                               # In case of an error
        Data         => {                                 # result data payload after Operation
            Errors => {                                   # In case of an error
                item => [
                    {
                        ErrorCode => '1',
                        Val1      => 'Error Description',
                        Val2      => 'Error Detail 1',
                        Val3      => 'Error Detail 2',
                        Val4      => 'Error Detail 3',

                    },
                ],
            },
            PersonMaps => {                               # Mapping of person IDs
                Item => {
                    PersonId    => '0001',
                    PersonIdExt => '5050',
                },
            },
            PrdIctId => '2011032400001', # Incident number in the provider (help desk system)
                                         # type="n0:char32", only for ReplicateIncident
        },
    };

=cut

sub TicketSync {
    my ( $Self, %Param ) = @_;

    # we need an operation
    my $FunctionName = 'Kernel::GenericInterface::Operation::SolMan::Common::TicketSync()';
    if ( !IsStringWithData( $Param{Operation} ) ) {
        return $Self->_ReturnError(
            ErrorCode    => 9,
            ErrorMessage => "Got no Operation in $FunctionName",
        );
    }
    my $OperationConfig =
        $Self->{Webservice}->{Config}->{Provider}->{Operation}->{ $Param{Operation} };

    # we need Data structure
    if ( !IsHashRefWithData( $Param{Data} ) ) {
        return $Self->_ReturnError(
            ErrorCode    => 9,
            ErrorMessage => "Got no Data in $FunctionName",
        );
    }

    # check needed head params
    if ( !IsHashRefWithData( $Param{Data}->{IctHead} ) ) {
        return $Self->_ReturnError(
            ErrorCode    => 9,
            ErrorMessage => "Got no Data->IctHead in $FunctionName",
        );
    }
    my %ErrorCodeByGuid = (
        IncidentGuid  => 1,
        RequesterGuid => 2,
        ProviderGuid  => 3,
    );
    for my $Guid (qw(IncidentGuid ProviderGuid RequesterGuid)) {
        if ( !IsStringWithData( $Param{Data}->{IctHead}->{$Guid} ) ) {
            return $Self->_ReturnError(
                ErrorCode => $ErrorCodeByGuid{$Guid} || 9,
                ErrorMessage => "Got no Data->IctHead->$Guid in $FunctionName",
            );
        }
    }

    # check if ProviderGuid and RequesterGuid differ
    my $ProviderGuid  = $Param{Data}->{IctHead}->{ProviderGuid};
    my $RequesterGuid = $Param{Data}->{IctHead}->{RequesterGuid};
    if ( $ProviderGuid eq $RequesterGuid ) {
        return $Self->_ReturnError(
            ErrorCode => 4,
            ErrorMessage =>
                "ProviderGuid and RequesterGuid are equal '$RequesterGuid' in $FunctionName",
        );
    }

    # check if SystemGuid entries exist
    my $LocalSystemGuid = $Self->LocalSystemGuid();
    if ( !IsStringWithData($LocalSystemGuid) ) {
        return $Self->_ReturnError(
            ErrorCode    => 9,
            ErrorMessage => "Missing LocalSystemGuid in $FunctionName",
        );
    }
    my $RemoteSystemGuid = $OperationConfig->{RemoteSystemGuid};
    if ( !IsStringWithData($RemoteSystemGuid) ) {
        return $Self->_ReturnError(
            ErrorCode    => 9,
            ErrorMessage => "Missing RemoteSystemGuid in $FunctionName",
        );
    }

    # check if ProviderGuid and RequesterGuid match remote system guid and local system guid
    my %SystemGuids = (
        $LocalSystemGuid  => 1,
        $RemoteSystemGuid => 1,
    );
    for my $SystemGuid (qw(ProviderGuid RequesterGuid)) {
        delete $SystemGuids{ $Param{Data}->{IctHead}->{$SystemGuid} };
    }
    if ( scalar keys %SystemGuids ) {
        my $SystemGuidErrorCode;
        if ( $SystemGuids{$LocalSystemGuid} ) {
            $SystemGuidErrorCode = 9;
        }
        else {
            $SystemGuidErrorCode = 13;
        }
        return $Self->_ReturnError(
            ErrorCode => $SystemGuidErrorCode,
            ErrorMessage =>
                "Invalid RequesterGuid '$RequesterGuid' or ProviderGuid '$ProviderGuid'"
                . " in $FunctionName",
        );
    }

    #TODO add person mapping

    # get state from data
    my $NewState;
    if ( IsHashRefWithData( $Param{Data}->{IctAdditionalInfos} ) ) {

        # in case there is only one additional info entry
        if (
            IsHashRefWithData( $Param{Data}->{IctAdditionalInfos}->{item} )
            && $Param{Data}->{IctAdditionalInfos}->{item}->{AddInfoAttribute} eq 'SAPUserStatus'
            && IsStringWithData( $Param{Data}->{IctAdditionalInfos}->{item}->{AddInfoValue} )
            )
        {
            $NewState = $Param{Data}->{IctAdditionalInfos}->{item}->{AddInfoValue};
        }

        # in case there are more than one additional info entries
        elsif ( IsArrayRefWithData( $Param{Data}->{IctAdditionalInfos}->{item} ) ) {
            ADDINFO:
            for my $AddInfo ( @{ $Param{Data}->{IctAdditionalInfos}->{item} } ) {
                next ADDINFO if !IsStringWithData( $AddInfo->{AddInfoAttribute} );
                next ADDINFO if $AddInfo->{AddInfoAttribute} ne 'SAPUserStatus';
                last ADDINFO if !IsStringWithData( $AddInfo->{AddInfoValue} );
                $NewState = $AddInfo->{AddInfoValue};
                last ADDINFO;
            }
        }
    }

    # create new ticket
    my $TicketID;
    my $IncidentGuidTicketFlagName = "GI_$Self->{WebserviceID}_SolMan_IncidentGuid";
    if ( $Param{Operation} eq 'ProcessIncident' || $Param{Operation} eq 'ReplicateIncident' ) {
        $TicketID = $Self->{TicketObject}->TicketCreate(
            Title => $Param{Data}->{IctHead}->{ShortDescription} || '',
            Queue => $OperationConfig->{Queue}                   || 'Raw',
            Lock  => 'unlock',
            Priority => $Param{Data}->{IctHead}->{Priority},
            State => $NewState || 'new',

            # TODO: replace with actual customer id and user from person mapping
            CustomerID   => $Param{Data}->{IctHead}->{ReporterId} || '',
            CustomerUser => $Param{Data}->{IctHead}->{ReporterId} || '',

            # TODO: replace with actual agent from person mapping (AgentId)
            OwnerID => 1,
            UserID  => 1,
        );
        if ( !$TicketID ) {
            my $ErrorMessage = $Self->{LogObject}->GetLogEntry(
                Type => 'error',
                What => 'Message',
            );
            return $Self->_ReturnError(
                ErrorCode    => 9,
                ErrorMessage => "$ErrorMessage in $FunctionName",
            );
        }

        # remember incident guid for further communication
        my $IncidentGuidSuccess = $Self->{TicketObject}->TicketFlagSet(
            TicketID => $TicketID,
            Key      => $IncidentGuidTicketFlagName,
            Value    => $Param{Data}->{IctHead}->{IncidentGuid},
            UserID   => 1,
        );
        if ( !$IncidentGuidSuccess ) {
            return $Self->_ReturnError(
                ErrorCode    => 9,
                ErrorMessage => "Could not set ticket flag in $FunctionName",
            );
        }

        # remember solman incident id
        my $IncidentIdSuccess = $Self->{TicketObject}->TicketFlagSet(
            TicketID => $TicketID,
            Key      => "GI_$Self->{WebserviceID}_SolMan_IncidentId",
            Value    => $Param{Data}->{IctId},
            UserID   => 1,
        );
        if ( !$IncidentIdSuccess ) {
            return $Self->_ReturnError(
                ErrorCode    => 9,
                ErrorMessage => "Could not set ticket flag in $FunctionName",
            );
        }
    }

    # update ticket
    else {

        # find ticket based on IncidentGuid
        my @Tickets = $Self->{TicketObject}->TicketSearch(
            Result     => 'ARRAY',
            Limit      => 2,
            TicketFlag => {
                $IncidentGuidTicketFlagName => $Param{Data}->{IctHead}->{IncidentGuid},
            },
            UserID     => 1,
            Permission => 'rw',
        );

        # only if exactly one ticket can be found
        if ( scalar @Tickets != 1 ) {
            return $Self->_ReturnError(
                ErrorCode => 9,
                ErrorMessage =>
                    'Could not find unique ticket for IncidentGuid'
                    . " '$Param{Data}->{IctHead}->{IncidentGuid}' in $FunctionName",
            );
        }

        $TicketID = $Tickets[0];

        # get existing ticket
        my %Ticket = $Self->{TicketObject}->TicketGet(
            TicketID => $TicketID,
            UserID   => 1,
        );

        # get last sync timestamp, ticket change time and last article change time for comparison
        my %TicketFlags = $Self->{TicketObject}->TicketFlagGet(
            TicketID => $TicketID,
            UserID   => 1,
        );
        my $LastSync      = $TicketFlags{"GI_$Self->{WebserviceID}_SolMan_SyncTimestamp"};
        my $TicketChanged = $Self->{TimeObject}->TimeStamp2SystemTime(
            String => $Ticket{Changed},
        );
        my @ArticleIDs = $Self->{TicketObject}->ArticleIndex(
            TicketID => $TicketID,
        );
        my $LastArticleCreated;
        if (@ArticleIDs) {
            my %Article = $Self->{TicketObject}->ArticleGet(
                ArticleID => $ArticleIDs[-1],
                UserID    => 1,
            );
            $LastArticleCreated = $Article{IncomingTime};
        }

        # if the ticket or an article was updated after the last sync, simulate a ticket lock
        if ( !$LastSync || $LastSync < $TicketChanged || $LastSync < $LastArticleCreated ) {
            return $Self->_ReturnError(
                ErrorCode => 11,
                ErrorMessage =>
                    "Ticket is not completely synchronized, cannot update at $FunctionName",
            );
        }

        # update AgentId if necessary
        # TODO: implement

        # update Priority if necessary
        if ( $Param{Data}->{IctHead}->{Priority} ne $Ticket{Priority} ) {
            my $PrioritySuccess = $Self->{TicketObject}->TicketPrioritySet(
                TicketID => $TicketID,
                Priority => $Param{Data}->{IctHead}->{Priority},
                UserID   => 1,
            );
            if ( !$PrioritySuccess ) {
                return $Self->_ReturnError(
                    ErrorCode    => 9,
                    ErrorMessage => "Could not update ticket priority in $FunctionName",
                );
            }
        }

        # update ReporterId if necessary
        # TODO: implement

        # update State if necessary
        if ( $NewState && $NewState ne $Ticket{State} ) {
            my $StateSuccess = $Self->{TicketObject}->TicketStateSet(
                State    => $NewState,
                TicketID => $TicketID,
                UserID   => 1,
            );
            if ( !$StateSuccess ) {
                return $Self->_ReturnError(
                    ErrorCode    => 9,
                    ErrorMessage => "Could not update ticket state in $FunctionName",
                );
            }
        }

        # update Title if necessary
        if ( $Param{Data}->{IctHead}->{ShortDescription} ne $Ticket{Title} ) {
            my $TitleSuccess = $Self->{TicketObject}->TicketTitleUpdate(
                Title    => $Param{Data}->{IctHead}->{ShortDescription},
                TicketID => $TicketID,
                UserID   => 1,
            );
            if ( !$TitleSuccess ) {
                return $Self->_ReturnError(
                    ErrorCode    => 9,
                    ErrorMessage => "Could not update ticket title in $FunctionName",
                );
            }
        }
    }

    # create articles from IctStatements
    my $LastArticleID;
    if (
        IsHashRefWithData( $Param{Data}->{IctStatements} )
        && $Param{Data}->{IctStatements}->{item}
        )
    {

        # allow for a single statement or several statements
        my @Statements;
        if ( ref $Param{Data}->{IctStatements}->{item} eq 'ARRAY' ) {
            @Statements = @{ $Param{Data}->{IctStatements}->{item} };
        }
        else {
            @Statements = ( $Param{Data}->{IctStatements}->{item} );
        }

        STATEMENT:
        for my $Statement (@Statements) {
            next STATEMENT if !IsHashRefWithData($Statement);
            next STATEMENT if !IsHashRefWithData( $Statement->{Texts} );
            next STATEMENT if !$Statement->{Texts}->{item};

            # allow for single item or several items
            my @Items;
            if ( ref $Statement->{Texts}->{item} eq 'ARRAY' ) {
                @Items = @{ $Statement->{Texts}->{item} };
            }
            else {
                @Items = ( $Statement->{Texts}->{item} );
            }

        # construct article subject
        # TODO construct like this (with person mapping): FirstName LastName (PersonIdExt) Timestamp
            my $Subject;
            my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = $Statement->{Timestamp} =~
                m{ \A ( \d{4} ) ( \d{2} ) ( \d{2} ) ( \d{2} ) ( \d{2} ) ( \d{2} ) \z }xms;
            if ( $Year && $Month && $Day && $Hour && $Minute && $Second ) {
                $Subject .= " $Day.$Month.$Year $Hour:$Minute:$Second (+0)";
            }

            # construct the text body from multiple item nodes
            my $Body .= join "\n", @Items;

            # create article
            my $ArticleID = $Self->{TicketObject}->ArticleCreate(
                TicketID    => $TicketID,
                ArticleType => $Statement->{TextType},

                # TODO use actual sender type if PersonId is set
                SenderType => 'system',

                # TODO use actual agent/customer if PersonId is set
                From           => 'SolMan',
                Subject        => $Subject || 'Statement from SolMan',
                Body           => $Body,
                Charset        => 'utf-8',
                MimeType       => 'text/plain',
                HistoryType    => 'AddNote',
                HistoryComment => 'Statement from SolMan',
                UserID         => 1,
            );
            if ( !$ArticleID ) {
                my $ErrorMessage = $Self->{LogObject}->GetLogEntry(
                    Type => 'error',
                    What => 'Message',
                );
                return $Self->_ReturnError(
                    ErrorCode    => 9,
                    ErrorMessage => "$ErrorMessage in $FunctionName",
                );
            }

            # remember article id for possible attachments
            $LastArticleID = $ArticleID;
        }
    }

    # create attachments from IctAttachments
    if (
        IsHashRefWithData( $Param{Data}->{IctAttachments} )
        && $Param{Data}->{IctAttachments}->{item}
        )
    {

        # allow for a single attachment or several attachments
        my @Attachments;
        if ( ref $Param{Data}->{IctAttachments}->{item} eq 'ARRAY' ) {
            @Attachments = @{ $Param{Data}->{IctAttachments}->{item} };
        }
        else {
            @Attachments = ( $Param{Data}->{IctAttachments}->{item} );
        }

        ATTACHMENT:
        for my $Attachment (@Attachments) {

            # ignore attachment deletions (delete flag set and != ' ')
            next ATTACHMENT if $Attachment->{Delete} && $Attachment->{Delete} ne ' ';

            # if no article was created yet, create one to attach attachments to
            if ( !$LastArticleID ) {
                $LastArticleID = $Self->{TicketObject}->ArticleCreate(
                    TicketID       => $TicketID,
                    ArticleType    => 'note-internal',
                    SenderType     => 'system',
                    From           => 'SolMan',
                    Subject        => "Attachment(s) from SolMan",
                    Body           => '',
                    Charset        => 'utf-8',
                    MimeType       => 'text/plain',
                    HistoryType    => 'AddNote',
                    HistoryComment => 'Attachment(s) from SolMan',
                    UserID         => 1,
                );
                if ( !$LastArticleID ) {
                    my $ErrorMessage = $Self->{LogObject}->GetLogEntry(
                        Type => 'error',
                        What => 'Message',
                    );
                    return $Self->_ReturnError(
                        ErrorCode    => 9,
                        ErrorMessage => "$ErrorMessage in $FunctionName",
                    );
                }
            }

            my $AttachmentSuccess = $Self->{TicketObject}->ArticleWriteAttachment(
                Content     => MIME::Base64::decode_base64( $Attachment->{Data} ),
                Filename    => $Attachment->{Filename},
                ContentType => $Attachment->{MimeType},
                ArticleID   => $LastArticleID,
                UserID      => 1,
            );
            if ( !$AttachmentSuccess ) {
                my $ErrorMessage = $Self->{LogObject}->GetLogEntry(
                    Type => 'error',
                    What => 'Message',
                );
                return $Self->_ReturnError(
                    ErrorCode    => 9,
                    ErrorMessage => "$ErrorMessage in $FunctionName",
                );
            }
        }
    }

    # close ticket
    if ( $Param{Operation} eq 'CloseIncident' ) {

        # use state from data or default from webservice configuration alternatively
        my $CloseState = $NewState || $OperationConfig->{CloseState};
        my $CloseSuccess = $Self->{TicketObject}->TicketStateSet(
            State    => $CloseState,
            TicketID => $TicketID,
            UserID   => 1,
        );
        if ( !$CloseSuccess ) {
            return $Self->_ReturnError(
                ErrorCode    => 9,
                ErrorMessage => "Could not close ticket in $FunctionName",
            );
        }
    }

    # set synchronization timestamp
    my $SyncTimestampSetSuccess = $Self->{TicketObject}->TicketFlagSet(
        TicketID => $TicketID,
        Key      => "GI_$Self->{WebserviceID}_SolMan_SyncTimestamp",
        Value    => $Self->{TimeObject}->SystemTime(),
        UserID   => 1,
    );
    if ( !$SyncTimestampSetSuccess ) {
        return $Self->_ReturnError(
            ErrorCode    => 9,
            ErrorMessage => "Could not set ticket flag in $FunctionName",
        );
    }

    # prepare return data
    my $ReturnData = {
        Data => {
            Errors => '',

            # TODO add for person maps
            PersonMaps => '',
            PrdIctId   => '',
        },
        Success => 1,
    };

    # get ticket number to return to solman
    if ( $Param{Operation} eq 'ProcessIncident' || $Param{Operation} eq 'ReplicateIncident' ) {
        my %Ticket = $Self->{TicketObject}->TicketGet(
            TicketID => $TicketID,
            UserID   => 1,
        );
        $ReturnData->{Data}->{PrdIctId} = $Ticket{TicketNumber};
    }

    # return result
    return $ReturnData;
}

=begin Internal:

=item LocalSystemGuid()

generates a SystemGuid for this system. This will return the SystemID as a MD5 sum in upper case
to match SolMan style.

    my $LocalSystemGuid = $CommonObject->LocalSystemGuid();

=cut

sub LocalSystemGuid {
    my ( $Self, %Param ) = @_;

    # get SystemID
    my $SystemID = $Self->{ConfigObject}->Get('SystemID') || 10;

    # convert SystemID to MD5 string
    my $SystemIDMD5 = $Self->{MainObject}->MD5sum(
        String => $SystemID,
    );

    # conver to upper case to match SolMan style
    return uc $SystemIDMD5;
}

=item _ReturnError()

helper function to return an error message from within TicketSync() in the way
SolMan expects it. See TicketSync() for how the error structure looks like.

    my $Return = $CommonObject->_ReturnError(
        ErrorCode    => 9,
        ErrorMessage => 'An error occured',
    );

=cut

sub _ReturnError {
    my ( $Self, %Param ) = @_;

    $Self->{DebuggerObject}->Error( Summary => "$Param{ErrorCode}: $Param{ErrorMessage}" );

    # set error return messages according to error code
    my %Val1ByErrorCode = (
        1  => 'missing incident GUID',
        2  => 'missing requester GUID',
        3  => 'missing provider GUID',
        4  => 'requester GUID and provider GUID are equal',
        11 => 'Incident is locked',
    );

    # return structure
    return {
        Success      => 0,
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
        Data         => {
            Errors => {
                item => [
                    {
                        ErrorCode => $Param{ErrorCode},
                        Val1      => $Val1ByErrorCode{ $Param{ErrorCode} } || $Param{ErrorMessage},
                        Val2      => undef,
                        Val3      => undef,
                        Val4      => undef,
                    }
                ],
            },
            PersonMaps => '',
            PrdIctId   => '',
        },
    };
}

1;

=end Internal:

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

=head1 VERSION

$Revision: 1.23 $ $Date: 2011-04-19 05:14:19 $

=cut
