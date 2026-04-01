import re

with open('./Mistia/App/RootTabView.swift', 'r') as f:
    content = f.read()

search = """  private var collapsedTint: Color {
    Color(red: 0.43, green: 0.23, blue: 0.76).opacity(colorScheme == .dark ? 0.78 : 0.64)
  }"""

replace = """  private var collapsedTint: Color {
    Color(red: 0.43, green: 0.23, blue: 0.76).opacity(colorScheme == .dark ? 0.18 : 0.12)
  }"""

search2 = """      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.98))
        .opacity(isExpanded ? 0 : 1)
        .scaleEffect(isExpanded ? 0.72 : 1)
        .frame(width: Self.collapsedSize, height: Self.collapsedSize)
        .animation(.easeInOut(duration: 0.16), value: isExpanded)"""

replace2 = """      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(red: 0.65, green: 0.45, blue: 0.98))
        .opacity(isExpanded ? 0 : 1)
        .scaleEffect(isExpanded ? 0.72 : 1)
        .frame(width: Self.collapsedSize, height: Self.collapsedSize)
        .background {
            Circle()
                .stroke(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.3), lineWidth: 1)
                .opacity(isExpanded ? 0 : 1)
                .scaleEffect(isExpanded ? 0.72 : 1)
                .animation(.easeInOut(duration: 0.16), value: isExpanded)
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)"""

content = content.replace(search, replace).replace(search2, replace2)

with open('./Mistia/App/RootTabView.swift', 'w') as f:
    f.write(content)
