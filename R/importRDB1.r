
#' Function to return data from the NWIS RDB 1.0 format
#'
#' This function accepts a url parameter that already contains the desired
#' NWIS site, parameter code, statistic, startdate and enddate. It is not
#' recommended to use the RDB format for importing multi-site data. 
#'
#' @param obs_url character containing the url for the retrieval or a file path to the data file.
#' @param asDateTime logical, if \code{TRUE} returns date and time as POSIXct, if \code{FALSE}, Date
#' @param tz character to set timezone attribute of datetime. Default converts the datetimes to UTC 
#' (properly accounting for daylight savings times based on the data's provided tz_cd column).
#' Recommended US values include "UTC","America/New_York","America/Chicago", "America/Denver","America/Los_Angeles",
#' "America/Anchorage","America/Honolulu","America/Jamaica","America/Managua","America/Phoenix", and "America/Metlakatla".
#' For a complete list, see \url{https://en.wikipedia.org/wiki/List_of_tz_database_time_zones}
#' @param convertType logical, defaults to \code{TRUE}. If \code{TRUE}, the function will convert the data to dates, datetimes,
#' numerics based on a standard algorithm. If false, everything is returned as a character
#' @return A data frame with the following columns:
#' \tabular{lll}{
#' Name \tab Type \tab Description \cr
#' agency_cd \tab character \tab The NWIS code for the agency reporting the data\cr
#' site_no \tab character \tab The USGS site number \cr
#' datetime \tab POSIXct \tab The date and time of the value converted to UTC (if asDateTime = \code{TRUE}), \cr 
#' \tab character \tab or raw character string (if asDateTime = FALSE) \cr
#' tz_cd \tab character \tab The time zone code for datetime \cr
#' code \tab character \tab Any codes that qualify the corresponding value\cr
#' value \tab numeric \tab The numeric value for the parameter \cr
#' tz_cd_reported \tab The originally reported time zone \cr
#' }
#' Note that code and value are repeated for the parameters requested. The names are of the form 
#' XD_P_S, where X is literal, 
#' D is an option description of the parameter, 
#' P is the parameter code, 
#' and S is the statistic code (if applicable).
#' If a date/time (dt) column contained incomplete date and times, a new column of dates and time was inserted. This could happen
#' when older data was reported as dates, and newer data was reported as a date/time.
#' 
#' There are also several useful attributes attached to the data frame:
#' \tabular{lll}{
#' Name \tab Type \tab Description \cr
#' url \tab character \tab The url used to generate the data \cr
#' queryTime \tab POSIXct \tab The time the data was returned \cr
#' comment \tab character \tab Header comments from the RDB file \cr
#' }
#' @export
#' @examples
#' site_id <- "02177000"
#' startDate <- "2012-09-01"
#' endDate <- "2012-10-01"
#' offering <- "00003"
#' property <- "00060"
#' 
#' obs_url <- constructNWISURL(site_id,property,
#'          startDate,endDate,"dv",format="tsv")
#' \donttest{
#' data <- importRDB1(obs_url)
#' 
#' urlMultiPcodes <- constructNWISURL("04085427",c("00060","00010"),
#'          startDate,endDate,"dv",statCd=c("00003","00001"),"tsv")
#' multiData <- importRDB1(urlMultiPcodes)
#' unitDataURL <- constructNWISURL(site_id,property,
#'          "2020-10-30","2020-11-01","uv",format="tsv") #includes timezone switch
#' unitData <- importRDB1(unitDataURL, asDateTime=TRUE)
#' qwURL <- constructNWISURL(c('04024430','04024000'),
#'           c('34247','30234','32104','34220'),
#'          "2010-11-03","","qw",format="rdb") 
#' qwData <- importRDB1(qwURL, asDateTime=TRUE, tz="America/Chicago")
#' iceSite <- '04024000'
#' start <- "2015-11-09"
#' end <- "2015-11-24"
#' urlIce <- constructNWISURL(iceSite,"00060",start, end,"uv",format="tsv")
#' ice <- importRDB1(urlIce, asDateTime=TRUE)
#' iceNoConvert <- importRDB1(urlIce, convertType=FALSE)
#' }
#' # User file:
#' filePath <- system.file("extdata", package="dataRetrieval")
#' fileName <- "RDB1Example.txt"
#' fullPath <- file.path(filePath, fileName)
#' importUserRDB <- importRDB1(fullPath)
#' 
importRDB1 <- function(obs_url, asDateTime=TRUE, convertType = TRUE, tz="UTC"){
  
  if(tz == ""){
    tz <- "UTC" 
  }
  
  tz <- match.arg(tz, OlsonNames())

  if(file.exists(obs_url)){
    doc <- obs_url
  } else {
    doc <- getWebServiceData(obs_url, encoding='gzip')
    if("warn" %in% names(attr(doc, "headerInfo"))){
      data <- data.frame()
      attr(data, "headerInfo") <- attr(doc,"headerInfo")
      attr(data, "url") <- obs_url
      attr(data, "queryTime") <- Sys.time()
      
      return(data)
    }
  }
  
  readr.total <- readr::read_lines(doc)
  total.rows <- length(readr.total)
  readr.meta <- readr.total[grep("^#", readr.total)]
  meta.rows <- length(readr.meta)
  header.names <- strsplit(readr.total[meta.rows+1],"\t")[[1]]
  types.names <- strsplit(readr.total[meta.rows+2],"\t")[[1]]
  data.rows <- total.rows - meta.rows - 2



  if(data.rows > 0){
    if(convertType){
      readr.data <- readr::read_delim(file = doc, delim = "\t",
                                      skip = meta.rows + 2,
                                      guess_max = data.rows,
                                      show_col_types = FALSE,
                                      col_names = FALSE)  
    } else {
      readr.data <- readr::read_delim(file = doc, delim = "\t",
                                      skip = meta.rows + 2,
                                      col_types = readr::cols(.default = "c"),
                                      show_col_types = FALSE,
                                      col_names = FALSE)      
    }
    
    if(nrow(readr.data) > 0){
      names(readr.data) <- header.names

      readr.data <- as.data.frame(readr.data)
      
      if(convertType){
        
        if(length(grep("_va", names(readr.data))) > 0 ){ 
          #note... if we simply convert any _va to numeric...we lose some QW censoring information from some formats
          vaCols <- grep("_va", names(readr.data))
          
          for(i in vaCols){
            readr.data[[i]] <- tryCatch({
              as.numeric(readr.data[[i]])
            },
            warning=function(cond) {
              message(paste("Column",i,"contains characters that cannot be automatically converted to numeric."))
              return(readr.data[[i]])
            }
            )
          }
    
        }

        if (asDateTime & convertType){
      
          header.suffix <- sapply(strsplit(header.names,"_"), function(x)x[length(x)])
          header.base <- substr(header.names,1,nchar(header.names)-3)
          
          dt_cols <- unique(header.base[header.suffix %in% c("dt","tm")])
          
          if(all(c("sample","sample_end") %in% dt_cols)){
            if("sample_start_time_datum_cd" %in% header.names){
              readr.data[,"tz_cd"] <- readr.data[,"sample_start_time_datum_cd"]
    
              readr.data[,"sample_start_time_datum_cd_reported"] <- readr.data[,"sample_start_time_datum_cd"]
              readr.data[,"sample_end_time_datum_cd_reported"] <- readr.data[,"sample_start_time_datum_cd"]
              readr.data <- readr.data[,names(readr.data)[names(readr.data) != "sample_start_time_datum_cd"]]
            }
          }
          
          for(i in dt_cols){
            
            if(all(c(paste0(i,"_dt"),paste0(i,"_tm")) %in% header.names)){
              varname <- paste0(i,"_dateTime")
    
              varval <- suppressWarnings(lubridate::parse_date_time(paste(readr.data[,paste0(i,"_dt")],
                                                                          readr.data[,paste0(i,"_tm")]), 
                                                                    c("%Y-%m-%d %H:%M:%S","%Y-%m-%d %H:%M"),
                                                                    tz = "UTC"))
            
              if(!all(is.na(varval))){
                readr.data[,varname] <- varval
                if(paste0(i, "_tz_cd") %in% names(readr.data)){
                  tz.name <- paste0(i, "_tz_cd") 
                } else {
                  tz.name <- paste0(i,"_time_datum_cd")
                }
                
                if(tz.name %in% names(readr.data)){
                  readr.data <- convertTZ(readr.data,tz.name,varname,tz)
                }
              }
            }
          }
    
          if("tz_cd" %in% names(readr.data)){
            date.time.cols <- which(sapply(readr.data, function(x) inherits(x, "POSIXct")))
            if(length(date.time.cols) > 0){
                readr.data <- convertTZ(readr.data,"tz_cd",date.time.cols,tz, flip.cols=FALSE)
            }
          }
          
          if("DATE" %in% header.names){
            readr.data[,"DATE"] <- lubridate::parse_date_time(readr.data[,"DATE"], "Ymd")
          }
          
          if(all(c("DATE","TIME","TZCD") %in% header.names)){
            varname <- "DATETIME"
            varval <- as.POSIXct(lubridate::fast_strptime(paste(readr.data[,"DATE"],readr.data[,"TIME"]), "%Y-%m-%d %H%M%S", tz = "UTC"))
            readr.data[,varname] <- varval
            readr.data <- convertTZ(readr.data,"TZCD",varname,tz, flip.cols=TRUE)
          }
          
          if("sample_dateTime" %in% names(readr.data)){
            names(readr.data)[names(readr.data) == "sample_dateTime"] <- "startDateTime"
          }
          
        }
        row.names(readr.data) <- NULL
        
      }
    }
  } else {
    readr.data <- data.frame(matrix(vector(), 0, length(header.names),
                                    dimnames=list(c(), header.names)),
                             stringsAsFactors=FALSE)
  }

  names(readr.data) <- make.names(names(readr.data))
  
  # People get confused having the tz_cd_reported next to the POSIXs:
  
  if("tz_cd_reported" %in% names(readr.data)){
    new_order <- names(readr.data)
    new_order <- c(new_order[!new_order %in% c("tz_cd_reported","tz_cd")], "tz_cd")
    readr.data <- readr.data[,new_order]
  }
  
  attr(readr.data, "queryTime") <- Sys.time()
  if(!file.exists(obs_url)){
    attr(readr.data, "url") <- obs_url
    attr(readr.data, "headerInfo") <- attr(doc, "headerInfo")
  }

  if("spec" %in% names(attributes(readr.data))){
    attr(readr.data, "spec") <- NULL
  }
  
  attr(readr.data, "comment") <- readr.meta
  
  return(readr.data)
  
}

convertTZ <- function(df, tz.name, date.time.cols, tz, flip.cols=TRUE){
  
  offsetLibrary <- data.frame(offset=c(5, 4, 6, 5, 7, 6, 8, 7, 9, 8, 10, 10, 0, 0, 0, 0),
                              code=c("EST","EDT","CST","CDT","MST","MDT","PST","PDT","AKST","AKDT","HAST","HST","UTC","", NA, "GMT"),
                              stringsAsFactors = FALSE)

  offset <- offsetLibrary$offset[match(df[,tz.name], offsetLibrary$code)]

  df[,paste0(tz.name,"_reported")] <- df[,tz.name,drop=FALSE]
  
  df[,date.time.cols] <- df[,date.time.cols] + offset*60*60
  
  for(i in date.time.cols){
    df[,i] <- as.POSIXct(df[,i])
    if(tz != ""){
      attr(df[,i], "tzone") <- tz
      df[,tz.name] <- tz
    } else {
      attr(df[,i], "tzone") <- "UTC"
      df[!is.na(df[,i]),tz.name] <- "UTC"
    }
  }


  
  if(flip.cols){
    reported.col <- which(names(df) %in% paste0(tz.name,"_reported"))
    orig.col <- which(names(df) %in% tz.name)
    
    new.order <- 1:ncol(df)
    new.order[orig.col] <- reported.col
    new.order[reported.col] <- orig.col
    
    df <- df[,new.order]
  }
  
  if(all(is.na(df[,date.time.cols]))){
    df[,date.time.cols] <- NULL
  }
  
  return(df)
}

fixErrors <- function(readr.data, readr.data.char, message.text, FUN, ...){
  FUN <- match.fun(FUN)
  badCols <- attr(readr.data, "problems")[["col"]] 
  int.message <- grep(message.text, attr(readr.data, "problems")[["expected"]])
  if(length(int.message) > 0){
    unique.bad.cols <- unique(badCols[int.message])
    index.col <- as.integer(gsub("X","",unique.bad.cols))
    
    for(i in index.col){
      readr.data[,i] <- tryCatch({
        FUN(readr.data.char[[i]], ...)
      }, warning=function(cond){
        readr.data.char[[i]]
      })
      attr(readr.data, "problems") <- attr(readr.data, "problems")[attr(readr.data, "problems")[["col"]] != paste0("X",i),]
    }
  }
  return(readr.data)
}

read_delim_check_quote <- function(..., total.rows){
  
  if(total.rows <= 0){
    total.rows <- 1
  }
  rdb.data <- suppressWarnings(readr::read_delim(..., 
                                                 show_col_types = FALSE,
                                                 guess_max = total.rows))
  
  if(nrow(rdb.data) < total.rows){
    rdb.data <- suppressWarnings(readr::read_delim(..., quote = "", 
                                                   show_col_types = FALSE,
                                                   guess_max = total.rows))
  }
  
  return(rdb.data)
  
}

