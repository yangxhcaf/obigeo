#' Single time slice,network-based compositional (e.g. biogeographic) partitioning 
#' 
#' This function runs network-based compositional partitioning on a contingency matrix.
#' 
#' @param contingency (\code{matrix}) Numeric matrix, species in rows, localities in columns. 
#' 
#' @param bipartite \code{logical} Setting this argument to \code{FALSE} will project the bipartite graph calculated from the contingency matrix, and make a unipartite grpah of the localities. 
#' 
#' @param sampcorr Can be either "occ", "dom" or a named numeric vector, where the names are the column names of \code{contingency}. 
#' @param feedback (\code{logical}) Should the functions output information about progress?
#' 
#' @param method Community clustering method. "infomap" "louvain" "netcarto" NULL: network is output
#' 
#' @param console \code{logical} Argument specifying whether an igraph, or a console application should be used. Currently only implemented for 'infomap'.
#' @param onlyloc \code{logical} Argumnet valid only if bipartite=TRUE. Should the taxa be reported too?
#' 
#' @param export Path to save the graph in rgexf format
#'
#' 
#' @export
groupNet <- function(contingency, bipartite=FALSE, method="infomap", export=NULL, console=FALSE, sampcorr=NULL, feedback=FALSE, onlyloc=TRUE, ...){
	# copy the contingency matrix
	origCont <-contingency
	# convert to incidence matrix
	contingency[contingency>1]<-1
		
	# for the network approaches
	# create a graph from all these - transpose!
	graph<-igraph::graph_from_incidence_matrix(contingency)
	
	# remove this to free up some memory
	cCont <- colnames(contingency)
	rm(contingency)
	gc()

	# with the bipartite graph
	if(bipartite){
		# something to be done
		if(!is.null(method)){
			if(method=="infomap"){
				if(console){
					infomapConsole(graph, bipartite,...)
				}else{
					if(feedback) fb("Infomap from igraph.")

					# try the infomap grouping on the bipartite graph
					infoIgraphBi<-igraph::cluster_infomap(graph)
					grouping <-igraph::membership(infoIgraphBi)
					class(grouping) <- "numeric"
					
					bCell<-names(grouping)%in%cCont
					cellGroup<-grouping[bCell]
					taxGroup<-grouping[!bCell]
					
					# final output
					grouping<-list()
					grouping[[1]]<-cellGroup
					grouping[[2]]<-taxGroup
				
				}
			}

			# by default return only locality information
			if(onlyloc) grouping<-grouping[[1]]
		# the output should be the graph
		}else{
			grouping<-graph
		}

	# with the unipartite graph
	}else{
		# 1. use only the projection
		graph <- igraph::bipartite_projection(graph, which="true")

		# 2. do the sampling intensity correction
		if(!is.null(sampcorr)){
			# switch
			if(length(sampcorr)==1){
				# the number of occurrences define the correction parameter
				if(sampcorr=="occ"){
					sampVect<- apply(origCont, 2, sum)
				}
				# the number of occurrences from the dominant taxon
				if(sampcorr=="dom"){
					sampVect<- apply(origCont,2, function(x){
						max(x)
					})
				}
			}else{
				sampVect <- sampcorr
			}

			# run correction function (collection-based entries are passed here!)
			graph <- siCorr(graph, sampVect)
		}

		# if something is to be done (method!=NULL)
		if(!is.null(method)){
			# 3different methods
			if(method=="infomap"){
				if(console){
					grouping <- infomapConsole(graph, bipartite,...)
				# run from igraph	
				} else{
					if(feedback) fb("Infomap from igraph.")
					
					# clustering
					infoIgraph <- igraph::cluster_infomap(graph) 
					grouping <-igraph::membership(infoIgraph)
					class(grouping) <- "numeric"

				} # end igraph
	
			} # end infomap
			
			if(method=="louvain"){
				infoIgraph <- igraph::cluster_louvain(graph) 
				grouping <-igraph::membership(infoIgraph)
				class(grouping) <- "numeric"
			}

			if(method=="netcarto"){
				if(feedback) fb("rNetCarto")
				adj <- as.matrix(igraph::as_adjacency_matrix(graph))
				ncRes <- rnetcarto::netcarto(adj, bipartite=FALSE)
				grouping<-as.numeric(as.factor(as.character(ncRes[[1]]$module)))
				names(grouping)<-as.character(ncRes[[1]]$name)
			
			} # end netcarto method
			
		}else{ # end NULL method	
			grouping <- graph
		} 

		if(!is.null(export) ){
			if(!is.null(method)){
				if(feedback) fb("Exporting graph.")
				group<-grouping[igraph::V(graph)$name]
				igraph::V(graph)$group <- as.numeric(group)
			#	igraph::V(graph)$colour <- allHex[as.numeric(group)]
			}
			gLocGexf <- rgexf::igraph.to.gexf(graph)
			f <- file(export)
			writeLines(gLocGexf$graph, con = f)
			close(f)
		}
		 # end export

		# the output should be the graph	
		
	} # bipartite=FALSE

	return(grouping)

}

# stolen fomr: https://www.r-bloggers.com/identifying-the-os-from-r/
get_os <- function(){
  sysinf <- Sys.info()
  if (!is.null(sysinf)){
    os <- sysinf['sysname']
    if (os == 'Darwin')
      os <- "osx"
  } else { ## mystery machine
    os <- .Platform$OS.type
    if (grepl("^darwin", R.version$os))
      os <- "osx"
    if (grepl("linux-gnu", R.version$os))
      os <- "linux"
  }
  tolower(os)
}


#' Function to run the infomap console application from within R.
#' 
#' This function reaches out from R, runs infomap, and loads its output to R. The infomap executable should be added to the system path environment variable (could be run from any directory).
#' 
#' @param graph (\code{igraph}) A graph.
#' 
#' @param bipartite (\code{logical}) Is the graph bipartite? The readin function will use this piece of information.
#' 
#' @param cargs Argumentation run with the console
#' 
#' @param feedback (\code{logical}) Should the functions output information about progress?
#' 
#' @export
infomapConsole<-function(graph, bipartite,cargs=NULL, feedback=FALSE){
	if(bipartite){
		if(feedback) fb("Writing graph to harddrive.")
		# 1. start by writing a graph to the harddrive
		# generate a temporary file
		tempd <- tempdir()
		igraph::write.graph(graph, file=paste(tempd,"/graph.net", sep=""), format="pajek")
		
		# determine os type
		OS <- get_os() 
		if(OS=="linux"){
			# 2. run infomap with the desired parameters
			command <- paste(
				"./Infomap ",
				tempd,"/graph.net ",
				tempd,"/ ",
				cargs,
				sep=""
			)
			
		}
		if(OS=="windows"){
			command <- paste(
				"Infomap.exe ",
				tempd,"\\temp\\graph.net ",
				tempd,"\\temp\\ ",
				cargs,
				sep=""
			)
		}
		if(!OS%in%c("linux", "windows")){
			stop("Not yet!")
		}
		
		if(feedback) fb("Starting the console application.")
		# run all this
		system(command, ignore.stdout=T, wait=TRUE)
		
		fb("Reading membership.")
		# 3. read in the results
		if(OS=="linux") inputPath <-paste(tempd,"/graph.tree",sep="")
		if(OS=="windows") inputPath <-paste(tempd,"\\graph.tree",sep="")
		grouping<-loadDotTree(file=inputPath)
		rownames(grouping) <- names(igraph::V(graph))
		
		bCell<-rownames(grouping)%in%colnames(cr)
		cellGroup<-grouping[bCell,]
		taxGroup<-grouping[!bCell,]
		
		# final output
		grouping<-list()
		grouping[[cell]]<-cellGroup
		grouping[[tax]]<-taxGroup
			

	}else{
		if(feedback) fb("Writing graph to harddrive.")
		# 1. start by writing a graph to the harddrive
		tempd <- tempdir()
		igraph::write.graph(graph, file=paste(tempd,"/graph.net", sep=""), format="pajek")
		
		# 2. run infomap with the desired parameters
		# determine os type
		OS <- get_os() 
		if(OS=="linux"){
			# 2. run infomap with the desired parameters
			command <- paste(
				cpath,"/./Infomap ",
				tempd,"/graph.net ",
				tempd,"/",
				cargs,
				sep=""
			)
			
		}
		if(OS=="windows"){
			command <- paste(
				cpath,"\\Infomap.exe ",
				tempd,"\\temp\\graph.net ",
				tempd,"\\temp\\ ",
				cargs,
				sep=""
			)
		}
		if(!OS%in%c("linux", "windows")){
			stop("Not yet!")
		}

		if(feedback) fb("Starting the console application.")
		# run all this
		system(command, ignore.stdout=T, wait=TRUE)
		
		if(feedback) fb("Reading membership.")
		# 3. read in the results
		if(OS=="linux") inputPath <-paste(tempd,"/graph.tree",sep="")
		if(OS=="windows") inputPath <-paste(tempd,"\\graph.tree",sep="")
		grouping<-loadDotTree(file=inputPath)
		rownames(grouping) <- names(igraph::V(graph))
				
	}

	return(grouping)

}



# sampling intensity correction function
siCorr <- function(gLoc, sampvec){
	edgelist<-igraph::get.edgelist(gLoc)
		
	sumDivider<- apply(edgelist, 1, function(x){
		cell1<-sampvec[x[1]]
		cell2<-sampvec[x[2]]
		(cell1+cell2)
	
	})
	
	igraph::E(gLoc)$weight<- igraph::E(gLoc)$weight/sumDivider
	return(gLoc)
}




########################################################
# Additional utility functions

getListElement<-function(li, n, unlist=T){
	res <- lapply(li, function(x) x[n])
	
	if(unlist){
		unlist(res)
	}
	return(res)
}


loadDotTree <- function(file, simple=T){
	connect<-file(file)
	everyLine<-readLines(connect)
	
	close(connect)
	
	everyLine<-everyLine[3:length(everyLine)]
	total<-strsplit(everyLine," ")
	
	flow <- as.numeric(getListElement(total, 2))
	name <- as.character(getListElement(total, 3))
	name <- gsub("\"", "", name)
	index <- as.numeric(getListElement(total, 4))
	
	hier<- as.character(getListElement(total, 1))
	listHier<-strsplit(hier, ":")
	
	elementNo<-unlist(lapply(listHier, length))
	
	hierMat <- matrix(NA, ncol=max(elementNo), nrow=length(elementNo))
	colnames(hierMat) <- paste("h", 1:ncol(hierMat), sep="")
	for(i in 1:max(elementNo)){
		 hierMat[,i]<- as.numeric(getListElement(listHier,i))
	
	}
	
	res<-data.frame(flow=flow, index=index, stringsAsFactors=F)
	rownames(res)<-name
	
	res<-cbind(res, hierMat)
	
	res <- res[order(res$index),]
	
	if(simple){
		return(res[,colnames(hierMat)])
	}
	
	# force garbage collection
	gc()

	return(res)
}

# loadDotTree(file="Data/Graphs/gLoc.tree")

