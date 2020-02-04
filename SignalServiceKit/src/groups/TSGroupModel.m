//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"
#import "UIImage+OWS.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const int32_t kGroupIdLengthV1 = 16;
const int32_t kGroupIdLengthV2 = 32;

NSUInteger const TSGroupModelSchemaVersion = 1;

@interface TSGroupModel ()

@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@end

#pragma mark -

@implementation TSGroupModel

@synthesize groupName = _groupName;

#if TARGET_OS_IOS

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
{
    self = [super init];
    if (!self) {
        return self;
    }

    _groupId = groupId;
    _groupName = name;
    _groupAvatarData = avatarData;
    _groupMembers = members;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    OWSAssertDebug([GroupManager isValidGroupId:groupId groupsVersion:self.groupsVersion]);

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    OWSAssertDebug([GroupManager isValidGroupId:self.groupId groupsVersion:self.groupsVersion]);

    if (_groupModelSchemaVersion < 1) {
        NSArray<NSString *> *_Nullable memberE164s = [coder decodeObjectForKey:@"groupMemberIds"];
        if (memberE164s) {
            NSMutableArray<SignalServiceAddress *> *memberAddresses = [NSMutableArray new];
            for (NSString *phoneNumber in memberE164s) {
                [memberAddresses addObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
            }
            _groupMembers = [memberAddresses copy];
        } else {
            _groupMembers = @[];
        }
    }

    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    if (self.groupAvatarData == nil) {
        UIImage *_Nullable groupImage = [coder decodeObjectForKey:@"groupImage"];
        if ([groupImage isKindOfClass:[UIImage class]]) {
            self.groupAvatarData = [TSGroupModel dataForGroupAvatar:groupImage];
        }
    }

    return self;
}

- (GroupsVersion)groupsVersion
{
    return GroupsVersionV1;
}

- (GroupMembership *)groupMembership
{
    return [[GroupMembership alloc] initWithV1Members:[NSSet setWithArray:self.groupMembers]];
}

- (GroupAccess *)groupAccess
{
    return GroupAccess.forV1;
}

- (uint32_t)groupV2Revision
{
    return 0;
}

- (nullable NSData *)groupSecretParamsData
{
    return nil;
}

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image
{
    if (image == nil) {
        return nil;
    }
    const CGFloat kMaxDimension = 800;
    if (image.pixelWidth > kMaxDimension ||
        image.pixelHeight > kMaxDimension) {
        CGFloat thumbnailSizePixels = MIN(kMaxDimension, MIN(image.pixelWidth, image.pixelHeight));
        image = [image resizedImageToFillPixelSize:CGSizeMake(thumbnailSizePixels, thumbnailSizePixels)];

        if (image == nil ||
            image.pixelWidth > kMaxDimension ||
            image.pixelHeight > kMaxDimension) {
            OWSLogVerbose(@"Could not resize group avatar: %@",
                          NSStringFromCGSize(image.pixelSize));
            OWSFailDebug(@"Could not resize group avatar.");
            return nil;
        }
    }
    NSData *_Nullable data = UIImagePNGRepresentation(image);
    if (data.length < 1) {
        OWSFailDebug(@"Could not convert group avatar to PNG.");
        return nil;
    }
    // We should never hit this limit, given the max dimension above.
    const NSUInteger kMaxLength = 500 * 1000;
    if (data.length > kMaxLength) {
        OWSLogVerbose(@"Group avatar data length: %lu (%@)",
                      (unsigned long)data.length,
                      NSStringFromCGSize(image.pixelSize));
        OWSFailDebug(@"Group avatar data has invalid length.");
        return nil;
    }
    return data;
}

- (void)setGroupAvatarDataWithImage:(nullable UIImage *)image
{
    self.groupAvatarData = [TSGroupModel dataForGroupAvatar:image];
}

- (nullable UIImage *)groupAvatarImage
{
    return [UIImage imageWithData:self.groupAvatarData];
}

- (void)setGroupAvatarData:(nullable NSData *)groupAvatarData {
    if (_groupAvatarData.length > 0 && groupAvatarData.length < 1) {
        OWSFailDebug(@"We should never remove an avatar from a group with an avatar.");
        return;
    }
    _groupAvatarData = groupAvatarData;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    return [self isEqualToGroupModel:other];
}

- (BOOL)isEqualToGroupModel:(TSGroupModel *)other {
    if (self == other) {
        return YES;
    }
    if (![_groupId isEqualToData:other.groupId]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupName equalTo:other.groupName]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupAvatarData equalTo:other.groupAvatarData]) {
        return NO;
    }
    NSSet<SignalServiceAddress *> *myGroupMembersSet = [NSSet setWithArray:_groupMembers];
    NSSet<SignalServiceAddress *> *otherGroupMembersSet = [NSSet setWithArray:other.groupMembers];
    if (![myGroupMembersSet isEqualToSet:otherGroupMembersSet]) {
        return NO;
    }
    if (self.groupsVersion != other.groupsVersion) {
        return NO;
    }
    return YES;
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

- (NSString *)groupNameOrDefault
{
    NSString *_Nullable groupName = self.groupName;
    return groupName.length > 0 ? groupName : TSGroupThread.defaultGroupName;
}

+ (NSData *)generateRandomV1GroupId
{
    return [Randomness generateRandomBytes:kGroupIdLengthV1];
}

- (NSArray<SignalServiceAddress *> *)nonLocalGroupMembers
{
    return [self.groupMembers filter:^(SignalServiceAddress *groupMemberId) {
        return !groupMemberId.isLocalAddress;
    }];
}

// GroupsV2 TODO: This should be done via GroupManager.
- (void)updateGroupMembers:(NSArray<SignalServiceAddress *> *)groupMembers
{
    _groupMembers = [groupMembers copy];
    // GroupsV2 TODO: Remove stale keys from groupsV2MemberRoles.
}

@end

#pragma mark -

@interface TSGroupModelV2 ()

@property (nonatomic) GroupMembership *membership;
@property (nonatomic) GroupAccess *access;
@property (nonatomic) NSData *secretParamsData;
@property (nonatomic) uint32_t revision;

@end

#pragma mark -

@implementation TSGroupModelV2

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                groupMembership:(GroupMembership *)groupMembership
                    groupAccess:(GroupAccess *)groupAccess
                       revision:(uint32_t)revision
               secretParamsData:(NSData *)secretParamsData
{
    OWSAssertDebug(secretParamsData.length > 0);

    self = [super initWithGroupId:groupId
                             name:name
                       avatarData:avatarData
                          members:groupMembership.nonPendingMembers.allObjects];

    if (!self) {
        return self;
    }

    _membership = groupMembership;
    _secretParamsData = secretParamsData;
    _access = groupAccess;
    _revision = revision;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    return self;
}

- (GroupsVersion)groupsVersion
{
    return GroupsVersionV2;
}

- (GroupMembership *)groupMembership
{
    return self.membership;
}

- (GroupAccess *)groupAccess
{
    return self.access;
}

- (NSArray<SignalServiceAddress *> *)groupMembers
{
    return self.groupMembership.nonPendingMembers.allObjects;
}

- (uint32_t)groupV2Revision
{
    return self.revision;
}

- (nullable NSData *)groupSecretParamsData
{
    return self.secretParamsData;
}

- (BOOL)isEqualToGroupModel:(TSGroupModel *)other
{
    if (![other isKindOfClass:TSGroupModelV2.class]) {
        return NO;
    }
    if (![super isEqualToGroupModel:other]) {
        return NO;
    }
    if (self.groupV2Revision != other.groupV2Revision) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupSecretParamsData equalTo:other.groupSecretParamsData]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupAccess equalTo:other.groupAccess]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupMembership equalTo:other.groupMembership]) {
        return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
