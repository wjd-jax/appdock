import { Controller } from "@hotwired/stimulus"
import * as ActionCable from "@rails/actioncable"
import { AppDock } from "./appdock"
import { application } from "./application"

export default class extends Controller {
  static values = {
    env: String,
    rootUrl: String,
    appearance: String
  }

  connect() {
    if (this.isInitialized) {
      return
    }

    try {
      this.initAppDock()
      this.setupRailsDebugMode()
      this.switchDarkMode()
      this.isInitialized = true
    } catch (error) {
      console.error('GlobalController initialization error:', error)
    }
  }

  initAppDock() {
    AppDock.rootUrl = this.rootUrlValue
    AppDock.siteApperance = this.appearanceValue
    AppDock.env = this.envValue
  }

  switchDarkMode() {
    const appearance = AppDock.siteApperance
    this.setGoodJobThemeMode(appearance);
    if (appearance === "dark" || (appearance === "auto" && AppDock.isDarkMode())) {
      document.documentElement.setAttribute("data-bs-theme", "dark");
    } else if (appearance === "light" && AppDock.isDarkMode()) {
      var darkBrandImage = document.getElementsByClassName("dark-brand-image")
      Array.prototype.forEach.call(darkBrandImage, (element) => {
        element.remove()
      })
    }
  }

  setGoodJobThemeMode(appearance) {
    localStorage.setItem("good_job-theme", appearance);
  }

  setupRailsDebugMode() {
    application.debug = AppDock.isDevelopment()
    ActionCable.logger.enabled = AppDock.isDevelopment()
  }
}
