#import "IPPresetListCell.h"

@implementation IPPresetListCell

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        // NSTableCellView's textField outlet does not retain its value.
        NSTextField *nameLabel = [NSTextField labelWithString:@""];
        nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        _addressLabel = [NSTextField labelWithString:@""];
        _addressLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
        for (NSTextField *field in @[nameLabel, _addressLabel]) {
            field.lineBreakMode = NSLineBreakByTruncatingTail;
            field.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:field];
            [field.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10].active
                = YES;
            [field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10].active
                = YES;
        }

        self.textField = nameLabel;
        [self.textField.topAnchor constraintEqualToAnchor:self.topAnchor constant:8].active = YES;
        [_addressLabel.topAnchor constraintEqualToAnchor:self.textField.bottomAnchor constant:3]
            .active
            = YES;
        [self setBackgroundStyle:NSBackgroundStyleNormal];
    }

    return self;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
    [super setBackgroundStyle:style];
    BOOL selected = style == NSBackgroundStyleEmphasized;
    self.textField.textColor = selected ? NSColor.selectedControlTextColor : NSColor.labelColor;
    self.addressLabel.textColor
        = selected ? NSColor.selectedControlTextColor : NSColor.secondaryLabelColor;
}

@end
