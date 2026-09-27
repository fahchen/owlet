import SwiftUI

/// Settings-page building blocks from design/index.html (.group-title, .formrow, .form-field).

/// Muted 11pt group heading.
struct GroupTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11))
            .tracking(0.6)
            .foregroundStyle(RoseGlass.muted)
            .padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Label left, control right, hairline below.
struct FormRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(RoseGlass.muted)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 17)
        .overlay(alignment: .bottom) { RoseGlass.line.frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

/// 12pt label above a bordered input box.
struct FormField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).accessibilityHidden(true)
            content
        }
    }
}

/// Bordered near-white box shared by inputs and selects; rose ring while focused.
struct FieldBox: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(.white.opacity(0.6), in: .rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? RoseGlass.accent : RoseGlass.line, lineWidth: focused ? 2 : 1)
            }
    }
}

/// Menu-backed select styled like the prototype's `<select>`.
struct SelectField<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 10) {
                Text(options.first { $0.value == selection }?.label ?? "\(selection)")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RoseGlass.muted)
            }
            .foregroundStyle(RoseGlass.ink)
            .modifier(FieldBox())
            .contentShape(.rect(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(title)
    }
}

/// Keycap chip (`kbd`).
struct KbdChip: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 11))
            .foregroundStyle(RoseGlass.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoseGlass.keyFill, in: .rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(RoseGlass.line))
    }
}

/// Main-window page footer bar: status left, actions right.
struct PageFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading.font(.system(size: 11)).foregroundStyle(RoseGlass.muted)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(RoseGlass.footerFill)
        .overlay(alignment: .top) { RoseGlass.line.frame(height: 1) }
    }
}

extension RoseGlass {
    /// oklch(94% .012 350): recording / selected tint.
    static let tint = Color(red: 0.949, green: 0.91, blue: 0.926)
    /// oklch(98% .008 350 / .65)
    static let keyFill = Color(red: 0.988, green: 0.967, blue: 0.975).opacity(0.65)
}
