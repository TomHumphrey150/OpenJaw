enum RootState: Equatable {
    case booting
    case auth
    case hydrating
    case ready
    case fatal(message: String)
}
