FROM ubuntu:24.04

RUN \
    apt-get update && \
    apt-get -y upgrade && \
    apt-get install -y build-essential  \
        software-properties-common \
        default-jdk \
        ant \
        wget \
        git \
        python3 \
        curl \
        unzip


RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain stable -y

ENV PATH="/root/.cargo/bin:$PATH"

RUN mkdir -p /root/.local
RUN mkdir -p /root/workspace

WORKDIR /root/workspace

COPY . .

# TLA+ toolbox
RUN wget https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/TLAToolbox-1.8.0-linux.gtk.x86_64.zip

# sqlite jdbc
RUN wget https://github.com/xerial/sqlite-jdbc/releases/download/3.45.3.0/sqlite-jdbc-3.45.3.0.jar

RUN ls -l

# install TLA+ toolbox
RUN unzip TLAToolbox-1.8.0-linux.gtk.x86_64.zip
RUN cp -r toolbox /root/.local


# build sedeve TLA+ overwrite modules    
RUN git clone https://github.com/scuptio/SedeveModules.git
RUN cd SedeveModules && ant dist

RUN git clone https://github.com/tlaplus/CommunityModules.git

# copy .jar to toolbox folder,
RUN cp /root/workspace/sqlite-jdbc-3.45.3.0.jar /root/.local/toolbox
RUN cp /root/workspace/SedeveModules/dist/SedeveModules-deps.jar /root/.local/toolbox
# copy community modules
RUN cp -r /root/workspace/CommunityModules/modules /root/.local/toolbox

# build and install sedeve-kit
RUN git clone https://github.com/scuptio/sedeve-kit.git
RUN cd sedeve-kit && cargo install --path .


# build raft project
RUN git clone https://github.com/scuptio/scupt-raft.git
RUN cd scupt-raft && cargo build


# copy .tla to Model_1n
# Here, we only testing 1 nodes for monstration purposes only, ore nodes will take longer to execute model checking
RUN cp /root/workspace/scupt-raft/spec/*.tla  /root/workspace/scupt-raft/spec/model_check/Model_1n

# run TLC model checker
RUN cd /root/workspace/scupt-raft/spec/model_check/Model_1n  && \
    /root/.local/toolbox/plugins/org.lamport.openjdk.linux.x86_64_14.0.1.7/jre/bin/java \
        -XX:MaxDirectMemorySize=10240m \
        -Xmx10240m \
        -Dtlc2.tool.fp.FPSet.impl=tlc2.tool.fp.OffHeapDiskFPSet \
        -Dtlc2.overrides.TLCOverrides=tlc2.overrides.TLCOverrides:tlc2.overrides.SedeveTLCOverrides \
        -XX:+UseParallelGC \
        -DTLA-Library=/root/.local/toolbox/SedeveModules-deps.jar:/root/.local/toolbox/sqlite-jdbc-3.45.3.0.jar:/root/.local/toolbox/modules \
        -Dfile.encoding=UTF-8 \
        -classpath /root/.local/toolbox/plugins/org.lamport.tlatools_1.0.0.202406200007:/root/.local/toolbox/plugins/org.lamport.tlatools_1.0.0.202406200007/lib/*:/root/.local/toolbox/plugins/org.lamport.tlatools_1.0.0.202406200007/lib/javax.mail/*:/root/.local/toolbox/plugins/org.lamport.tlatools_1.0.0.202406200007/class:/root/.local/toolbox/plugins/org.lamport.tlatools_1.0.0.202406200007/lib/gson/*:/root/.local/toolbox/SedeveModules-deps.jar:/root/.local/toolbox/sqlite-jdbc-3.45.3.0.jar:/root/.local/toolbox/modules/* \
        -XX:+ShowCodeDetailsInExceptionMessages \
        tlc2.TLC \
        -fpbits 1 \
        -fp 111 \
        -config MC.cfg \
        -coverage 3 \
        -workers 2 \
        -noGenerateSpecTE \
        -tool -metadir \
        /root/workspace/scupt-raft/spec/model_check/Model_1n MC

# run generate trace
RUN sedeve_trace_gen  \
   # see MC.tla
   --state-db-path /root/workspace/scupt-raft/spec/model_check/Model_1n/action.db  \ 
   --out-trace-db-path /tmp/trace.db \
   --map-const-path  /root/workspace/scupt-raft/data/raft_map_const.json


# copy test data to project test data folder
RUN cp /tmp/trace.db /root/workspace/scupt-raft/data/raft_trace_1n.db
RUN cd /root/workspace/scupt-raft && cargo test --lib test_raft_1n::tests::test_raft_1node -- --exact
