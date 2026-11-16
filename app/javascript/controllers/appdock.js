var AppDock = AppDock || {}

const DEVELOPMENT_ENV = "development"

AppDock.isDarkMode = function () {
  return window.matchMedia("(prefers-color-scheme: dark)")
    .matches
}

AppDock.isDevelopment = function () {
  // env was given value in global_controller
  return AppDock.env === DEVELOPMENT_ENV
}

window.AppDock = AppDock

export { AppDock }